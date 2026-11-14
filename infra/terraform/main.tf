locals {
  app_dir   = "${path.module}/../../app"
  chart_dir = "${path.module}/../helm/mural"

  # Image tags derive from the content of what goes into each image. Unchanged sources
  # give the same tag (nothing is rebuilt on a second apply); a change gives a new tag,
  # which rebuilds, reloads and rolls the Deployment.
  image_sources = {
    api = concat(
      ["docker/api.Dockerfile"],
      [for f in sort(fileset(local.app_dir, "api/**")) : f],
    )
    web = concat(
      ["docker/web.Dockerfile"],
      [for f in sort(fileset(local.app_dir, "web/**")) : f],
    )
  }

  image_tags = {
    for name, files in local.image_sources :
    name => substr(sha256(join("", [for f in files : filesha256("${local.app_dir}/${f}")])), 0, 12)
  }

  images = {
    for name, tag in local.image_tags :
    name => {
      repository = "mural-${name}"
      tag        = tag
      ref        = "mural-${name}:${tag}"
      dockerfile = "docker/${name}.Dockerfile"
    }
  }

  url = var.http_port == 80 ? "http://${var.host}" : "http://${var.host}:${var.http_port}"

  # Non-sensitive chart values. The password goes separately through set_sensitive.
  mural_values = yamlencode({
    api = {
      autoscaling = { enabled = var.autoscaling_enabled }
      image = {
        repository = local.images.api.repository
        tag        = local.images.api.tag
      }
    }
    web = {
      image = {
        repository = local.images.web.repository
        tag        = local.images.web.tag
      }
    }
    postgres = {
      user     = var.db_user
      database = var.db_name
    }
    ingress = {
      className = "traefik"
      host      = var.host
    }
  })
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = abspath("${path.module}/.kube/config")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Label used to pin the ingress controller to the node that owns the port mappings.
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n",
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = var.http_port
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = 443
        host_port      = var.https_port
        protocol       = "TCP"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Images: built on the host and loaded into the kind node (there is no registry)
# ---------------------------------------------------------------------------

resource "terraform_data" "image" {
  for_each = local.images

  # Replaced (rebuild + reload) only when the cluster is recreated or the tag changes.
  triggers_replace = [kind_cluster.this.id, each.value.ref]

  provisioner "local-exec" {
    working_dir = local.app_dir
    command     = "docker build -t ${each.value.ref} -f ${each.value.dockerfile} ."
  }

  provisioner "local-exec" {
    command = "kind load docker-image ${each.value.ref} --name ${kind_cluster.this.name}"
  }
}

# ---------------------------------------------------------------------------
# Ingress controller
# ---------------------------------------------------------------------------

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  namespace        = "traefik"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    # The pod binds 80/443 of the kind node, which the cluster maps to the host.
    ports = {
      web       = { hostPort = 80 }
      websecure = { hostPort = 443 }
    }
    service      = { spec = { type = "ClusterIP" } }
    nodeSelector = { "ingress-ready" = "true" }
    tolerations = [{
      key      = "node-role.kubernetes.io/control-plane"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
    # A host port cannot be held by two pods at once, so the old pod goes first.
    updateStrategy = {
      type          = "RollingUpdate"
      rollingUpdate = { maxUnavailable = 1, maxSurge = 0 }
    }
    providers = {
      kubernetesIngress = {
        # There is no LoadBalancer address to publish on the Ingress status.
        publishedService = { enabled = false }
      }
    }
  })]
}

# ---------------------------------------------------------------------------
# Metrics (bonus): source of the CPU usage the API autoscaler reads
# ---------------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  count = var.autoscaling_enabled ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    # The kubelet certificates of a kind node are self-signed.
    args = ["--kubelet-insecure-tls"]
  })]

  depends_on = [kind_cluster.this]
}

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "mural" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "mural" {
  name      = "mural"
  chart     = local.chart_dir
  namespace = kubernetes_namespace_v1.mural.metadata[0].name

  # The migration is a post-install hook and the API only becomes Ready after it.
  # With wait = true Helm would wait for the API before running the hook: a deadlock.
  # Helm still blocks until the hook Job completes; readiness is awaited right below.
  wait    = false
  timeout = 600

  values = [local.mural_values]

  set_sensitive = [{
    name  = "postgres.password"
    value = var.db_password
    type  = "string"
  }]

  depends_on = [
    terraform_data.image,
    helm_release.traefik,
    helm_release.metrics_server,
  ]
}

# Makes "apply finished" mean "the Mural answers": waits for the rollouts.
resource "terraform_data" "rollout" {
  for_each = toset(["api", "web"])

  triggers_replace = [
    helm_release.mural.id,
    kind_cluster.this.id,
    sha256(local.mural_values),
  ]

  provisioner "local-exec" {
    command = "kubectl --kubeconfig \"${kind_cluster.this.kubeconfig_path}\" --namespace ${helm_release.mural.namespace} rollout status deployment/${helm_release.mural.name}-${each.key} --timeout=300s"
  }
}
