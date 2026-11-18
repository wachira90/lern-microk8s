# Trivy Image Scan บน Kubernetes MicroK8s

## สามารถ Run ใน Kubernetes MicroK8s ได้หรือไม่

ได้ครับ และ Trivy เหมาะมากสำหรับ Kubernetes / MicroK8s เพราะสามารถ Scan ได้ทั้ง:

1. Container Image
2. Running Containers
3. Kubernetes Cluster Configuration
4. Helm Charts
5. IaC (Terraform, Kubernetes YAML)
6. SBOM
7. Secrets

---

# วิธีที่ 1: Scan Images ที่กำลังใช้งานใน MicroK8s

## ดู Image ที่ Cluster ใช้งานอยู่

```bash
kubectl get pods -A -o jsonpath='{..image}' | tr -s '[[:space:]]' '\n' | sort | uniq
```

ตัวอย่างผลลัพธ์

```text
nginx:1.25.5
postgres:18.7-bookworm
quay.io/keycloak/keycloak:26.0.6
public.ecr.aws/karpenter/controller:v1.8.3
```

## ติดตั้ง Trivy

```bash
sudo apt-get install wget apt-transport-https gnupg

wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
| sudo apt-key add -

echo "deb https://aquasecurity.github.io/trivy-repo/deb generic main" \
| sudo tee /etc/apt/sources.list.d/trivy.list

sudo apt update
sudo apt install trivy
```

ตรวจสอบ Version

```bash
trivy version
```

## Scan Image ทีละตัว

```bash
trivy image nginx:1.25.5
```

```bash
trivy image postgres:18.7-bookworm
```

## แสดงเฉพาะ High และ Critical

```bash
trivy image --severity HIGH,CRITICAL postgres:18.7-bookworm
```

## แสดงเฉพาะช่องโหว่ที่ยังไม่ถูกแก้

```bash
trivy image --ignore-unfixed postgres:18.7-bookworm
```

---

# วิธีที่ 2: Scan Images ทั้ง Cluster อัตโนมัติ

```bash
kubectl get pods -A -o jsonpath='{..image}' \
| tr -s '[[:space:]]' '\n' \
| sort -u \
| while read image
 do
   echo "=================================="
   echo "Scanning $image"
   echo "=================================="

   trivy image \
     --severity HIGH,CRITICAL \
     --ignore-unfixed \
     $image
 done
```

---

# Export Report

## JSON

```bash
trivy image -f json -o report.json postgres:18.7-bookworm
```

## HTML

```bash
trivy image -f template -t "@contrib/html.tpl" -o report.html postgres:18.7-bookworm
```

---

# วิธีที่ 3: Scan Kubernetes Cluster ตรง ๆ

```bash
trivy kubernetes cluster
```

Scan:

- Pods
- Deployments
- DaemonSets
- RBAC
- NetworkPolicy
- SecurityContext
- Privileged Container

```bash
trivy kubernetes cluster --report summary
```

---

# วิธีที่ 4: Run Trivy ใน Kubernetes (MicroK8s)

```bash
kubectl create ns security
```

```bash
kubectl run trivy \
-n security \
--image=aquasec/trivy:latest \
-it --rm --restart=Never -- sh
```

ภายใน Pod

```bash
trivy image nginx:1.25.5
```

---

# วิธีที่ 5: Trivy Operator (แนะนำสำหรับ Production)

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update
```

```bash
helm install trivy-operator aqua/trivy-operator \
-n trivy-system \
--create-namespace
```

ตรวจสอบ Report

```bash
kubectl get vulnerabilityreports -A
kubectl get configauditreports -A
kubectl get clustercompliancereports
```

Trivy จะ Scan ใหม่อัตโนมัติเมื่อ:

- Pod เปลี่ยน
- Deployment เปลี่ยน
- Image เปลี่ยน

---

# แนวทางที่แนะนำสำหรับ MicroK8s

## ดึงรายการ Images ทั้งหมด

```bash
kubectl get pods -A -o jsonpath='{..image}' \
| tr -s '[[:space:]]' '\n' \
| sort -u
```

## Scan เฉพาะ HIGH / CRITICAL

```bash
for img in $(kubectl get pods -A -o jsonpath='{..image}' | tr ' ' '\n' | sort -u)
do
  echo "===== $img ====="
  trivy image --severity HIGH,CRITICAL --ignore-unfixed $img
done
```

## ติดตั้ง Trivy Operator

```bash
helm install trivy-operator aqua/trivy-operator \
-n trivy-system \
--create-namespace
```

## ตรวจสอบ Report

```bash
kubectl get vulnerabilityreports -A
kubectl get configauditreports -A
kubectl get exposedsecretreports -A
```

## คำสั่งเดียว Scan Images ทั้งหมดที่กำลังใช้งาน

```bash
kubectl get pods -A -o jsonpath='{..image}' \
| tr -s '[[:space:]]' '\n' \
| sort -u \
| xargs -I {} trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  {}
```

## Best Practice

สำหรับ Production Cluster แนะนำให้ใช้:

- Trivy Operator
- Prometheus
- Grafana

เพื่อทำ Continuous Vulnerability Monitoring และ Security Dashboard แบบอัตโนมัติ แทนการ Scan แบบ Manual
