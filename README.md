# Wisecow on Kubernetes

Wisecow is a tiny Bash web server that serves “wise” thoughts rendered through `cowsay`. This repository provides everything required to ship the application as a container and run it on Kubernetes with TLS termination and automated CI/CD.

## Application

- `wisecow.sh` runs an HTTP listener (default port `4499`) and streams fortunes back in a cow-themed ASCII banner.
- Ports and FIFO paths can be overridden through the `SRVPORT` and `RSPFILE` environment variables.

### Run without containers

```bash
sudo apt install fortune-mod cowsay netcat-openbsd -y
./wisecow.sh
```

Visit `http://localhost:4499`.

### Run with Docker

```bash
docker build -t wisecow:local .
docker run --rm -p 4499:4499 wisecow:local
```

Override the listening port with `-e SRVPORT=8080 -p 8080:8080` if required.

## Kubernetes deployment

Manifests live in `k8s/` and are bundled through Kustomize.

1. **Set the container registry location**  
   Update `k8s/kustomization.yaml` so `newName` points at the image location you push to (defaults to `ghcr.io/your-org/wisecow`).

2. **Create a TLS secret**  
   Provide a certificate that matches the ingress host (defaults to `wisecow.example.com`):
   ```bash
   kubectl create namespace wisecow
   kubectl -n wisecow create secret tls wisecow-tls \
     --cert=/path/to/cert.pem \
     --key=/path/to/key.pem
   ```
   If you use cert-manager, swap the secret creation with an appropriate `Certificate`/`Issuer` definition.

3. **Deploy**  
   ```bash
   kubectl apply -k k8s
   kubectl -n wisecow get all
   ```

4. **Validate TLS ingress**  
   Point DNS for `wisecow.example.com` (or your host) at the ingress controller and browse to `https://<host>/`.

Resources created:
- `Namespace` `wisecow`
- `Deployment` `wisecow` (2 replicas, HTTP readiness/liveness probes)
- `Service` `wisecow` (port 80 → pod port 4499)
- `Ingress` `wisecow` with TLS termination (`wisecow-tls` secret)

## GitHub Actions CI/CD

The workflow in `.github/workflows/ci-cd.yml` performs:

1. **Build & Push** (all pushes and PRs targeting `main`)
   - Builds the Docker image.
   - Tags it with `ghcr.io/<owner>/wisecow:<git-sha>` and `:latest`.
   - Pushes to GitHub Container Registry (GHCR).

2. **Deploy** (pushes to `main` only)
   - Applies the manifests from `k8s/`.
   - Updates the running deployment to the freshly pushed image.
   - Waits for rollout completion.

### Required repository secrets

| Secret | Description |
|--------|-------------|
| `GHCR_TOKEN` | Personal access token for GitHub Container Registry belonging to `poojasingh9490` with at least `write:packages` scope. |
| `KUBE_CONFIG_DATA` | Base64‑encoded kubeconfig with permissions to manage the `wisecow` namespace. |

> Create the PAT under the `poojasingh9490` account, then store it as a repo secret named `GHCR_TOKEN`.  
> Encode the kubeconfig with `base64 -w0 < kubeconfig` before pasting it into the secret field.

### Enable the workflow

1. Ensure the repository is **public** (as per project requirement).
2. Configure `Actions > General` permissions to allow GitHub Actions to create and approve pull requests if you use environments.
3. Add the `GHCR_TOKEN` secret (see table above) so the workflow can push to `ghcr.io/poojasingh9490`.
4. Add `KUBE_CONFIG_DATA` in `Settings > Secrets and variables > Actions`.
5. Adjust the ingress host and image registry in `k8s/` to match your environment.

## TLS considerations

- The provided ingress assumes an NGINX ingress controller. Update annotations as needed for other controllers.
- Certificates can be self-signed for testing but must match the ingress host. For production, prefer ACME via cert-manager or another trusted issuer.

## Next steps

- Hook ingress DNS to your cluster.
- Optionally tighten security (restrict `fortune` database, add PodSecurity standards, resource quotas).
- Extend the workflow with smoke tests before rollout if desired.
