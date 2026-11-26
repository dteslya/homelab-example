# homelab (example)

A working homelab, published as a template. It's the real config: OpenTofu,
Talos Linux, ArgoCD and Ansible. It's exported from a private repo by a
pipeline that rewrites anything identifying and stubs out every secret.
Read it, borrow from it, or fork it and swap in your own values.

Details in the blog post: https://example.com/blog/2026/11/26/my-homelab-and-self-hosting-setup

## Layout

```
main.tf, variables.tf, outputs.tf   root module: VMs, TrueNAS, outputs
modules/talos_config/               Talos machine configs (no cluster access)
modules/incus_vm/                   one Talos VM, booted via NoCloud
modules/kubernetes/                 etcd bootstrap, health wait, kubeconfig
bootstrap/                          ArgoCD install + root Application
argocd/apps/                        one Application / AppProject per app
argocd/<app>/                       flat Kustomize base for each app
ansible/                            OpenWrt routers + headscale VPS
scripts/                            Talos image import, helpers
```

## Adapting it

Everything that identified the original owner was replaced with a
placeholder:

| Placeholder | Meaning |
|---|---|
| `lab.example.com`, `example.com` | your domains |
| `10.0.x.x` | the LAN address plan (subnets are internally consistent) |
| `203.0.113.10` | the VPS public IP |
| `your-github-user` | the repo owner in ArgoCD `repoURL`s |
| `REPLACE_WITH_KUBESEAL_OUTPUT` | a SealedSecret value. Each file has a comment with the `kubectl create secret ... \| kubeseal` command that regenerates it |
| `vault.yml.example` | an ansible-vault file. Copy it to `vault.yml`, fill it in, then `ansible-vault encrypt` it |
| `Etc/UTC` | your timezone |

Rough order to stand it up:

1. Import a Talos nocloud image with `scripts/import-talos-image.sh`. Copy
   `terraform.tfvars.example` to `terraform.tfvars`, edit it, then run
   `tofu init && tofu apply`.
2. Point every `repoURL` at your fork, and add a read-only deploy key to
   ArgoCD.
3. Once the sealed-secrets controller is running, regenerate each
   `secret*.yaml` with the command in its header comment, then commit.
4. Apply `bootstrap/root-app.yaml`. ArgoCD takes it from there.

Cut whatever you don't need. Each app is a single `argocd/apps/<app>.yaml`
plus its `argocd/<app>/` directory.

## About this export

This repo is regenerated from the private one. See `PROVENANCE`. Issues
and questions are welcome, but pull requests can't be merged directly:
fixes are applied upstream and come back with the next export.
