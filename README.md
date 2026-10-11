## k8s-gitops-platform

Runs the Bookify React client on a local minikube cluster with Helm, plus a cluster-wide Prometheus/Grafana monitoring stack. There is also an Ansible playbook for putting nginx in front of the app on a plain VM.

### Layout

| Path | What it is |
|------|------------|
| `k8s/` | Helm chart for `bookify-client` (Deployment, Service, ConfigMap, Secret, Ingress) |
| `monitoring/values.yaml` | Values for `kube-prometheus-stack`, tuned for minikube |
| `nginx/` | Ansible playbook that installs nginx on a VM and reverse proxies port 3000 |
| `bookify/` | Local only, git-ignored. Holds the client source and your values file with Firebase keys |
| `Makefile` | Every command needed to run the project |

### Prerequisites

`minikube`, `kubectl`, `helm`, `git`, `make`. For the VM setup you also need `ansible`.

### Quick start

```bash
make clone
make values
```

Open `bookify/bookify-values.yaml` and replace the placeholders with your Firebase web app config. Then:

```bash
make all
```

That starts minikube with the ingress addon, builds the client image inside minikube, installs the app and the monitoring stack, and adds the `.local` hostnames to `/etc/hosts` (asks for sudo).

| URL | Service |
|-----|---------|
| http://bookify.local | Bookify client |
| http://grafana.local | Grafana, user `admin`, password from `make grafana-password` |
| http://prometheus.local | Prometheus |
| http://alertmanager.local | Alertmanager |

### Day to day

```bash
make status
make image TAG=0.0.2 && make app TAG=0.0.2
make app
make monitoring
make help
```

Always bump `TAG` when you rebuild the image. Minikube keeps the old image for a tag it already has.

`REACT_APP_API_URL` and `REACT_APP_IMG_BB_KEY` are baked in at build time, so put them in `bookify/bookify-client/.env` before `make image`. The Firebase values are read when the container starts and come from the values file.

### VM with nginx

Edit `nginx/inventory.ini` with your VM's address and user, then:

```bash
make vm
```

### Tear down

```bash
make app-down
make monitoring-down
make down
```

`make monitoring-down` leaves the Prometheus Operator CRDs in the cluster. Remove them with `kubectl delete crd -l app.kubernetes.io/part-of=kube-prometheus-stack` if nothing else uses them.

The first monitoring install takes a few minutes while minikube pulls images. Grafana shows as unavailable until it finishes its first start.
