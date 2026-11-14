# Mural de Recados — do compose ao cluster

Entrega do desafio "Do compose ao cluster: Docker, Kubernetes e Terraform" (MBA Full Cycle).
A aplicação em `app/api` e `app/web` não foi alterada; a entrega é a infraestrutura em volta dela.
O estado-alvo está em [`docs/arquitetura.md`](docs/arquitetura.md).

## Pré-requisitos

Docker, [kind](https://kind.sigs.k8s.io/), kubectl, curl e Terraform (>= 1.6) no `PATH`.
As portas 80 e 443 da máquina precisam estar livres (ou troque por `http_port` / `https_port`).

## Como rodar

### Cluster (a entrega)

```bash
cd infra/terraform
export TF_VAR_db_password='escolha-uma-senha'   # PowerShell: $env:TF_VAR_db_password = '...'
terraform init
terraform apply      # cria o cluster, as imagens, o Traefik e o Mural
terraform apply      # 0 added, 0 changed, 0 destroyed
terraform destroy    # remove tudo
```

Depois do primeiro `apply`, abra <http://mural.localtest.me>. Com `make`: `make up` e `make down`.

A senha também pode ir num `terraform.tfvars` (ignorado pelo git; modelo em
`terraform.tfvars.example`). Para usar o `kubectl`:
`kubectl --kubeconfig infra/terraform/.kube/config -n mural get pods`.

### Compose (só para conhecer a aplicação)

```bash
cp .env.example .env    # defina POSTGRES_PASSWORD
docker compose up
# http://localhost:8080
```

Sobe na ordem banco → migração → API → front, só com imagens oficiais.

## Tamanho da imagem da API

| Imagem | Tamanho |
|--------|---------|
| Antes: `golang:1.23-alpine`, a base do `go run` (sem contar código e módulos) | 370 MB |
| Depois: `app/docker/api.Dockerfile` (`scratch`) | 12,8 MB |

Medido com `docker image ls` na execução do workflow descrito em [Verificação](#verificação): cerca de 29 vezes menor.

## Decisões

**Docker**

- API em multi-stage: compila com `CGO_ENABLED=0` (binário estático, `-s -w`, `-trimpath`) e
  termina em `scratch`. A API só fala HTTP puro e Postgres dentro do cluster, então não precisa
  de certificados nem de timezone; `distroless` só acrescentaria peso. Roda como usuário sem
  privilégio (`65534`).
- Front na imagem oficial do nginx: o template vai para `/etc/nginx/templates`, e o próprio
  entrypoint aplica `API_UPSTREAM` no boot. A mesma imagem serve em qualquer ambiente.
- O contexto de build dos dois é `app/`.

**Helm**

- **Migração como hook `post-install,post-upgrade`.** Como `pre-install` ela rodaria antes de o
  Postgres existir. Como `post-install`, o Helm cria Secret, ConfigMaps e StatefulSet, roda o
  Job (que espera o banco aceitar conexão e aplica os `.sql` em ordem) e só retorna quando ele
  termina. Até lá `/readyz` falha e a API não recebe tráfego. As migrations são idempotentes,
  então rodar a cada release é seguro.
- **Probes.** API: liveness em `/healthz`, readiness em `/readyz`. Postgres: `pg_isready` via
  TCP, que só passa quando o servidor de verdade está aceitando conexão.
- **Secret.** `DATABASE_URL` e a senha do Postgres ficam num único Secret, gerado a partir de
  `postgres.password`, que é obrigatório e vazio no `values.yaml`. API, Postgres e Job leem por
  `secretKeyRef`. O resto da configuração (porta, upstream do nginx, host e nome do banco) fica
  num ConfigMap.
- **Postgres** em StatefulSet com `volumeClaimTemplates` e Service headless; os dados ficam em
  um subdiretório (`PGDATA`) do volume.
- Os pods da API e do front carregam o checksum da configuração, para reiniciarem quando ela muda.
- A API roda com sistema de arquivos somente leitura, sem capabilities e sem root.

**Terraform**

- **Cluster** com o provider `kind`: um nó com o label `ingress-ready=true` e as portas 80/443
  mapeadas. O kubeconfig fica em `infra/terraform/.kube/` (ignorado pelo git), sem tocar no
  `~/.kube/config`.
- **Imagens.** A tag é o hash do conteúdo que entra em cada imagem. Sem mudança no código, a tag
  é a mesma e o segundo `apply` não refaz nada; com mudança, a tag nova dispara build,
  `kind load docker-image` e o rollout do Deployment.
- **Traefik** pelo chart oficial, preso ao nó `ingress-ready` e escutando nas portas do nó
  (`hostPort`), já que no kind não há LoadBalancer.
- **Namespace `mural`** criado pelo provider `kubernetes`; o chart entra por `helm_release`.
- **`wait = false` no release do Mural.** Com `wait`, o Helm esperaria a API ficar `Ready` antes
  de rodar o hook de migração, e ela só fica `Ready` depois dele. O Helm continua bloqueando até
  o Job terminar. Em seguida o Terraform espera o rollout (`kubectl rollout status`) e pede `/` e
  `/api/messages` pelo Ingress até responderem, porque o Traefik ainda leva um instante para
  enxergar os pods prontos. Assim, `apply` concluído significa Mural respondendo.
- **Senha** pela variável sensível `db_password`, sem default, repassada ao chart com
  `set_sensitive`. Ela fica no state do Terraform, que é local e ignorado pelo git.

## Limitação conhecida

Trocar `db_password` depois da primeira instalação atualiza o Secret, mas não a senha já gravada
no banco (o Postgres só a define ao inicializar o volume). Para trocar, rode `destroy` e `apply`.

## Bônus

**HPA.** O chart traz um `HorizontalPodAutoscaler` da API (CPU a 60% do request, de 2 a 6
réplicas), ligado por `api.autoscaling.enabled`. O Terraform liga por padrão
(`autoscaling_enabled`) e instala o metrics-server, de onde o HPA lê o consumo. Com o HPA ligado
o Deployment não declara `replicas`, então o Terraform não desfaz a escala: o `apply` depois da
carga continua em `0 added, 0 changed, 0 destroyed`.

Prova de escala, com o k6 (`infra/k6/load.js`, 50 usuários virtuais por 3 minutos em
`GET /api/messages` pelo Ingress): a API foi de **2 para 6 réplicas**, atendendo cerca de
2.800 requisições por segundo. Para repetir: `make load` em um terminal e `make status` em outro.

**Makefile.** `make up` (init + apply), `make down` (destroy), `make status` e `make load`.

## Verificação

O workflow [`ciclo`](.github/workflows/ciclo.yml) roda a entrega inteira numa máquina limpa do
GitHub Actions e falha se algum passo não bater:

| Passo | Resultado |
|-------|-----------|
| `docker compose up` | 4 serviços no ar, recado criado e listado pelo proxy do nginx |
| Primeiro `terraform apply` | `11 added, 0 changed, 0 destroyed`; `/` e `/api` respondem pelo Ingress |
| Pods | nenhum restart; liveness em `/healthz`, readiness em `/readyz` |
| Segundo `terraform apply` | `0 added, 0 changed, 0 destroyed` |
| Carga com k6 | API escala de 2 para 6 réplicas |
| `terraform apply` depois da escala | `0 added, 0 changed, 0 destroyed` |
| `terraform destroy` | `11 destroyed`; sem cluster, sem container, state vazio |

Ele roda por disparo manual ou em branches `verify/*`.
