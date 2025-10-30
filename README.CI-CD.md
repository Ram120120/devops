# Wisecow CI/CD & Deployment Runbook

This document records the exact workflow we followed to containerise the Wisecow app, deploy it to Minikube with TLS, and automate delivery through GitHub Actions. It highlights every manual step, configuration decision, and issue encountered along the way.

---

## 1. Containerisation

1. **Base image & packages**  
   - Started from `debian:stable-slim`.
   - Installed runtime dependencies: `bash`, `ca-certificates`, `cowsay`, `fortune-mod`, `fortunes-min`, `netcat-openbsd`.
   - Added `/usr/games` to `PATH` because `fortune` and `cowsay` install there.

2. **Non-root execution**  
   - Created a dedicated system user `pooja` and adjusted ownership of `/app`.
   - Set `USER pooja` in the Dockerfile.

3. **Final Dockerfile**  
   ```dockerfile
   FROM debian:stable-slim
   ENV DEBIAN_FRONTEND=noninteractive \
       SRVPORT=4499 \
       PATH="/usr/games:${PATH}"

   RUN apt-get update \
       && apt-get install -y --no-install-recommends \
           bash ca-certificates cowsay fortune-mod fortunes-min netcat-openbsd \
       && rm -rf /var/lib/apt/lists/*

   WORKDIR /app
   COPY wisecow.sh /app/wisecow.sh
   RUN chmod +x /app/wisecow.sh \
       && useradd --system --home /nonexistent --shell /usr/sbin/nologin pooja \
       && chown -R pooja:pooja /app

   EXPOSE 4499
   USER pooja
   ENTRYPOINT ["./wisecow.sh"]
   ```

4. **Local build validation**  
   ```bash
   docker build -t ghcr.io/ram120120/wisecow:latest .
   docker run --rm -p 4499:4499 ghcr.io/ram120120/wisecow:latest
   curl http://localhost:4499/
   ```

---

## 2. Minikube deployment

1. **Prerequisites**
   - Minikube cluster running on host `dal2mddvkgvt02`.
   - NGINX ingress enabled: `minikube addons enable ingress`.
   - Namespace + TLS secret created:
     ```bash
     kubectl create namespace wisecow
     openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -out wisecow.crt -keyout wisecow.key \
       -subj "/CN=wisecow.local/O=Wisecow"
     kubectl -n wisecow create secret tls wisecow-tls \
       --cert=wisecow.crt --key=wisecow.key
     ```

2. **Image pull secret**  
   ```bash
   kubectl -n wisecow create secret docker-registry ghcr-cred \
     --docker-server=ghcr.io \
     --docker-username=ram120120 \
     --docker-password='<GHCR PAT with read/write packages>'
   ```

3. **Kustomize overlay**  
   `k8s/kustomization.yaml` pins the image to `ghcr.io/ram120120/wisecow:latest` and wires the namespace, deployment, service, and ingress (host `wisecow.local`).

4. **Apply manifests**
   ```bash
   kubectl apply -k k8s
   kubectl -n wisecow rollout status deployment/wisecow
   ```

5. **Ingress access**  
   ```bash
   echo "$(minikube ip) wisecow.local" | sudo tee -a /etc/hosts
   curl --cacert wisecow.crt --resolve wisecow.local:443:$(minikube ip) https://wisecow.local/
   ```

   Final output example:
   ```
   <pre> ________________________________________
   / You will inherit some money or a small \
   \ piece of land.                         /
    ----------------------------------------
           \   ^__^
            \  (oo)\_______
               (__)\       )\/\
                   ||----w |
                   ||     ||</pre>
   ```

---

## 3. GitHub Actions pipeline

Workflow stored at `.github/workflows/ci-cd.yml`. Structure:

1. **Build job (`ubuntu-latest`)**
   - Checks out repo.
   - Logs into GHCR using secrets `REGISTRY_USERNAME=ram120120` and `GHCR_TOKEN` (PAT on same account).
   - Builds and pushes image as `ghcr.io/ram120120/wisecow:{sha,latest}`.

2. **Deploy job (self-hosted runner `minikube`)**
   - Uses kubeconfig stored in secret `KUBE_CONFIG_DATA` (base64-encoded file with embedded certs).
   - Applies `k8s/` manifests and rolls out the new image.
   - Runs only on pushes to `main`.

3. **Secrets required**
   | Secret | Purpose |
   |--------|---------|
   | `GHCR_TOKEN` | GHCR PAT for `ram120120` with `write:packages`. |
   | `KUBE_CONFIG_DATA` | Embedded kubeconfig targeting the Minikube cluster. |

4. **Self-hosted runner**
   - Runner named `minikube` installed on the same host as the cluster for network access.
   - Deploy job configured with `runs-on: [self-hosted, minikube]`.

---

## 4. Issues encountered & fixes

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| GHCR tag uppercase | `repository name must be lowercase` | Forced lowercase owner (`IMAGE_NAME=ram120120/wisecow`). |
| GHCR push denied | `permission_denied: The requested installation does not exist` | Switched to PAT (`GHCR_TOKEN`) instead of `GITHUB_TOKEN`. |
| Deploy job cannot reach API | `dial tcp 192.168.49.2:8443: i/o timeout` | Added self-hosted runner on Minikube host. |
| Image pull unauthorized | `Failed to pull image`: unauthorized | Created `ghcr-cred` secret with PAT. |
| Container exits immediately | `Install prerequisites.` message | Added `/usr/games` to PATH and installed `fortunes-min`. |
| Container start failure | `unable to find user pooja` | Added `useradd --system pooja` to Dockerfile. |
| Logs show “No fortunes found” | fortune data missing | Installed `fortunes-min` package. |
| Ingress 404/connection refused | NGINX ingress disabled | Enabled `minikube addons enable ingress`. |
| TLS hostname not resolvable | `Could not resolve host` | Added `/etc/hosts` entry or used `--resolve` with curl. |

---

## 5. Operational checklist

1. Build & push:
   ```bash
   docker build -t ghcr.io/ram120120/wisecow:latest .
   docker push ghcr.io/ram120120/wisecow:latest
   ```
   *(or rely on GitHub Actions on `main` push)*

2. Deploy:
   ```bash
   kubectl apply -k k8s
   kubectl -n wisecow rollout status deployment/wisecow
   ```

3. Verify:
   ```bash
   kubectl -n wisecow get pods,svc,ingress
   curl --cacert wisecow.crt --resolve wisecow.local:443:$(minikube ip) https://wisecow.local/
   ```

4. If pods crash:
   ```bash
   kubectl -n wisecow describe pod <name>
   kubectl -n wisecow logs <name> --previous
   ```

---

## 6. Maintenance tips

- Rotate GHCR PAT before expiry; update both GitHub secret `GHCR_TOKEN` and Kubernetes pull secret `ghcr-cred`.
- Update TLS certificates and re-create the secret when they expire (or automate via cert-manager).
- If ingress host changes, update `k8s/ingress.yaml`, DNS/hosts entries, and redeploy.
- Monitor workflow runs under GitHub → Actions. Use the self-hosted runner logs (`~actions-runner/_diag`) for debugging.

---

### Final verification

After all fixes the deployment responds over TLS:

```bash
curl --cacert wisecow.crt --resolve wisecow.local:443:$(minikube ip) https://wisecow.local/
```

Output shows `cowsay` rendering a fortune, confirming the CI/CD pipeline and cluster resources operate end-to-end.
