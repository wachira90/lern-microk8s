# 5 Use Cases การนำ RBAC ไปใช้งานบน Kubernetes MicroK8s

ด้านล่างเป็น 5 Use Case ที่พบบ่อยสำหรับการนำ **Kubernetes RBAC บน MicroK8s** ไปใช้งาน โดยยึดหลัก **Least Privilege** คือให้สิทธิ์เฉพาะเท่าที่จำเป็น

> สมมติว่าเปิด RBAC แล้วด้วย `microk8s enable rbac`  
> หลังเปิดใช้งาน ควรตรวจสอบว่า automation หรือ kubeconfig เดิมยังเข้าถึง Cluster ได้ตามปกติ

---

## องค์ประกอบสำคัญของ RBAC

| Resource | ขอบเขต | หน้าที่ |
|---|---|---|
| `ServiceAccount` | Namespace | ตัวตนของ Pod หรือระบบ Automation |
| `Role` | Namespace | กำหนดสิทธิ์ภายใน Namespace |
| `RoleBinding` | Namespace | ผูก Role กับ User, Group หรือ ServiceAccount |
| `ClusterRole` | ทั้ง Cluster | กำหนดสิทธิ์ระดับ Cluster หรือใช้ซ้ำหลาย Namespace |
| `ClusterRoleBinding` | ทั้ง Cluster | ผูก ClusterRole กับตัวตนในระดับ Cluster |

หลักการสำคัญคือ:

```text
Subject                  Permission                 Binding
User/Group/ServiceAccount  <-- Role/ClusterRole <-- RoleBinding/ClusterRoleBinding
```

---

# Use Case 1: Developer ดูและแก้ไข Application ได้เฉพาะ Namespace ของตนเอง

## สถานการณ์

ทีม Developer ดูแล Application ใน Namespace `development` โดยต้องสามารถ:

- ดู Pod, Deployment และ Service
- ดู Log
- Restart Deployment
- Scale Deployment
- แก้ไข ConfigMap

แต่ไม่ควร:

- ลบ Namespace
- เข้าถึง Secret
- แก้ไข Application ใน `production`
- แก้ไข Node หรือ Cluster configuration

## ตัวอย่าง Manifest

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: development
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: development
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - configmaps
      - events
    verbs:
      - get
      - list
      - watch

  - apiGroups: [""]
    resources:
      - configmaps
    verbs:
      - create
      - update
      - patch

  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
    verbs:
      - get
      - list
      - watch
      - update
      - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: development
subjects:
  - kind: Group
    name: developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

นำไปใช้งาน:

```bash
microk8s kubectl apply -f developer-rbac.yaml
```

ทดสอบสิทธิ์:

```bash
microk8s kubectl auth can-i list pods \
  --namespace development \
  --as wachira \
  --as-group developers
```

```bash
microk8s kubectl auth can-i get secrets \
  --namespace development \
  --as wachira \
  --as-group developers
```

ผลที่ควรได้:

```text
yes
no
```

## เหมาะสำหรับ

- Dev, SIT และ UAT Namespace
- Cluster ที่หลายทีมใช้งานร่วมกัน
- ป้องกัน Developer แก้ไข Production โดยไม่ตั้งใจ

---

# Use Case 2: ทีม Support ดูสถานะและ Log ได้ แต่แก้ไข Resource ไม่ได้

## สถานการณ์

ทีม Application Support หรือ NOC ต้อง Troubleshoot ปัญหา เช่น:

- ดู Pod status
- ดู Deployment status
- ดู Event
- ดู Log
- ตรวจสอบ Service และ Endpoint

แต่ไม่สามารถ:

- ลบ Pod
- Restart Deployment
- Scale Deployment
- แก้ไข ConfigMap หรือ Secret

กรณีนี้เหมาะกับการสร้าง **Read-only Role**

## ตัวอย่าง Manifest

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: application-support-readonly
  namespace: production
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - endpoints
      - events
      - configmaps
    verbs:
      - get
      - list
      - watch

  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs:
      - get
      - list
      - watch

  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: application-support-readonly-binding
  namespace: production
subjects:
  - kind: Group
    name: application-support
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: application-support-readonly
  apiGroup: rbac.authorization.k8s.io
```

ทดสอบ:

```bash
microk8s kubectl auth can-i get pods \
  -n production \
  --as support-user \
  --as-group application-support
```

```bash
microk8s kubectl auth can-i get pods/log \
  -n production \
  --as support-user \
  --as-group application-support
```

```bash
microk8s kubectl auth can-i delete pods \
  -n production \
  --as support-user \
  --as-group application-support
```

ผลที่ควรได้:

```text
yes
yes
no
```

## จุดที่ต้องระวัง

การอ่าน `Secret` ไม่ใช่สิทธิ์ Read-only ธรรมดา เพราะผู้ที่อ่าน Secret ได้อาจนำ Credential ไปเข้าถึง Database, API หรือระบบอื่น ดังนั้นอย่าเพิ่ม `secrets` โดยไม่จำเป็น

---

# Use Case 3: CI/CD Deploy Application ได้เฉพาะ Application ที่กำหนด

## สถานการณ์

Jenkins, GitLab Runner, GitHub Actions หรือ Azure DevOps ต้อง Deploy Application ไปยัง Namespace `production`

ไม่ควรให้ CI/CD ใช้ kubeconfig ของ `admin` หรือ `cluster-admin` เพราะถ้า Pipeline หรือ Credential รั่ว ผู้โจมตีจะควบคุม Cluster ได้ทั้งหมด

ให้สร้าง `ServiceAccount` แยกสำหรับ Pipeline

## ตัวอย่าง Manifest

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-deployer
  namespace: production
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-deployer
  namespace: production
rules:
  - apiGroups: ["apps"]
    resources:
      - deployments
    resourceNames:
      - payment-api
    verbs:
      - get
      - update
      - patch

  - apiGroups: ["apps"]
    resources:
      - deployments
    verbs:
      - get
      - list
      - watch

  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - events
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-deployer-binding
  namespace: production
subjects:
  - kind: ServiceAccount
    name: app-deployer
    namespace: production
roleRef:
  kind: Role
  name: app-deployer
  apiGroup: rbac.authorization.k8s.io
```

สร้าง Token สำหรับ ServiceAccount:

```bash
microk8s kubectl create token app-deployer \
  --namespace production \
  --duration=1h
```

ทดสอบด้วย Impersonation:

```bash
microk8s kubectl auth can-i patch deployment/payment-api \
  -n production \
  --as system:serviceaccount:production:app-deployer
```

```bash
microk8s kubectl auth can-i patch deployment/customer-api \
  -n production \
  --as system:serviceaccount:production:app-deployer
```

ผลที่ควรได้:

```text
yes
no
```

## Deployment command ใน Pipeline

หาก Pipeline เปลี่ยนเฉพาะ Container Image:

```bash
kubectl set image deployment/payment-api \
  payment-api=registry.example.com/payment-api:2.1.0 \
  --namespace production
```

รอตรวจสอบ Rollout:

```bash
kubectl rollout status deployment/payment-api \
  --namespace production \
  --timeout=5m
```

## ข้อควรระวังสำคัญ

แม้ ServiceAccount จะไม่มีสิทธิ์อ่าน Secret แต่ถ้ามีสิทธิ์แก้ไข Deployment ก็อาจแก้ Pod template ให้ Mount Secret หรือใช้ ServiceAccount อื่นได้ จึงควรเสริมด้วย:

- Dedicated ServiceAccount สำหรับ Application
- Admission policy เช่น Kyverno หรือ OPA Gatekeeper
- จำกัด Registry ที่อนุญาต
- ปิด `automountServiceAccountToken` เมื่อ Application ไม่ต้องใช้ Kubernetes API
- หลีกเลี่ยง `create`, `delete` และ wildcard `*` หาก Pipeline ต้องเปลี่ยนเฉพาะ Image

---

# Use Case 4: Monitoring อ่าน Metrics และ Resource ทั่ว Cluster

## สถานการณ์

ระบบอย่าง Prometheus ต้องค้นหาและอ่านข้อมูลจากหลาย Namespace เช่น:

- Node
- Pod
- Service
- Endpoint
- Namespace
- ConfigMap
- Kubernetes API metrics

เพราะต้องอ่านข้าม Namespace จึงใช้ `ClusterRole` แต่ไม่จำเป็นต้องให้สิทธิ์ `cluster-admin`

## ตัวอย่าง Manifest

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-monitoring
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/metrics
      - nodes/proxy
      - pods
      - services
      - endpoints
      - namespaces
      - configmaps
    verbs:
      - get
      - list
      - watch

  - nonResourceURLs:
      - /metrics
      - /metrics/*
    verbs:
      - get

  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-monitoring-binding
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: monitoring
roleRef:
  kind: ClusterRole
  name: prometheus-monitoring
  apiGroup: rbac.authorization.k8s.io
```

ทดสอบ:

```bash
microk8s kubectl auth can-i list nodes \
  --as system:serviceaccount:monitoring:prometheus
```

```bash
microk8s kubectl auth can-i list pods \
  --all-namespaces \
  --as system:serviceaccount:monitoring:prometheus
```

```bash
microk8s kubectl auth can-i delete pods \
  -n production \
  --as system:serviceaccount:monitoring:prometheus
```

ผลที่ควรได้:

```text
yes
yes
no
```

## เหตุผลที่ใช้ ClusterRole

`Node` เป็น Cluster-scoped resource และ Prometheus ต้อง Discover Pod/Service หลาย Namespace ดังนั้น `Role` ใน Namespace เดียวไม่เพียงพอ

---

# Use Case 5: จำกัดสิทธิ์ DBA ให้ดูแล PostgreSQL StatefulSet เท่านั้น

## สถานการณ์

ทีม DBA ดูแล PostgreSQL บน MicroK8s และต้องสามารถ:

- ดู Pod และ Log ของ PostgreSQL
- ดู StatefulSet
- Scale หรือแก้ไข StatefulSet
- ตรวจสอบ PVC
- เข้าไปใน PostgreSQL Pod เพื่อ Troubleshoot

แต่ไม่ควร:

- แก้ไข Application อื่น
- ลบ PVC
- อ่าน Secret ทุกตัว
- จัดการ Node หรือ Namespace

## ตัวอย่าง Manifest

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: postgres-dba
  namespace: database
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - persistentvolumeclaims
      - events
    verbs:
      - get
      - list
      - watch

  - apiGroups: [""]
    resources:
      - pods/exec
    verbs:
      - create

  - apiGroups: ["apps"]
    resources:
      - statefulsets
    resourceNames:
      - postgresql
    verbs:
      - get
      - update
      - patch

  - apiGroups: ["apps"]
    resources:
      - statefulsets
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: postgres-dba-binding
  namespace: database
subjects:
  - kind: Group
    name: database-administrators
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: postgres-dba
  apiGroup: rbac.authorization.k8s.io
```

ทดสอบ:

```bash
microk8s kubectl auth can-i create pods/exec \
  -n database \
  --as dba-user \
  --as-group database-administrators
```

```bash
microk8s kubectl auth can-i patch statefulset/postgresql \
  -n database \
  --as dba-user \
  --as-group database-administrators
```

```bash
microk8s kubectl auth can-i delete persistentvolumeclaims \
  -n database \
  --as dba-user \
  --as-group database-administrators
```

ผลที่ควรได้:

```text
yes
yes
no
```

## ความเสี่ยงของ `pods/exec`

สิทธิ์ `pods/exec` มีความเสี่ยงสูง เพราะ User อาจ:

- อ่าน Environment Variable ภายใน Container
- อ่านไฟล์ที่ Mount มาจาก Secret
- เรียกใช้ ServiceAccount Token ของ Pod
- เข้าถึง Database ด้วยสิทธิ์ของ Container
- เคลื่อนที่ไปยังระบบอื่นใน Network

จึงควรให้เฉพาะทีมที่จำเป็น และแยก Namespace ของ Database ออกจาก Application อย่างชัดเจน

---

# สรุปทั้ง 5 Use Case

| Use Case | ตัวตน | Resource หลัก | RBAC ที่ใช้ |
|---|---|---|---|
| Developer | Group `developers` | Deployment, Pod, Service | Role + RoleBinding |
| Support Read-only | Group `application-support` | Pod, Log, Event | Role + RoleBinding |
| CI/CD Deployment | ServiceAccount `app-deployer` | Deployment ที่กำหนด | Role + RoleBinding |
| Prometheus Monitoring | ServiceAccount `prometheus` | Node และ Resource ทุก Namespace | ClusterRole + ClusterRoleBinding |
| PostgreSQL DBA | Group `database-administrators` | StatefulSet, Pod, PVC | Role + RoleBinding |

## คำสั่งตรวจสอบ RBAC ที่ควรใช้ประจำ

ดูสิทธิ์ทั้งหมดของตัวเอง:

```bash
microk8s kubectl auth can-i --list
```

ตรวจว่า ServiceAccount ทำอะไรได้บ้าง:

```bash
microk8s kubectl auth can-i --list \
  --as system:serviceaccount:production:app-deployer \
  --namespace production
```

ตรวจสอบ Binding:

```bash
microk8s kubectl get role,rolebinding -A
```

```bash
microk8s kubectl get clusterrole,clusterrolebinding
```

ดูรายละเอียด Role:

```bash
microk8s kubectl describe role developer \
  --namespace development
```

## แนวทางสำหรับ Production

1. หลีกเลี่ยงการแจก `cluster-admin` ให้ User หรือ Pipeline
2. ใช้ `Group` สำหรับบุคคล และ `ServiceAccount` สำหรับ Workload/Automation
3. แยก Role ตามหน้าที่ เช่น `developer`, `support-readonly`, `deployer`, `dba`
4. หลีกเลี่ยง `resources: ["*"]` และ `verbs: ["*"]`
5. อย่าให้สิทธิ์อ่าน `secrets` โดยไม่จำเป็น
6. ระวังสิทธิ์ `pods/exec`, `pods/attach`, `pods/portforward` และการแก้ Pod/Deployment เพราะสามารถใช้ยกระดับการเข้าถึงได้
7. ทดสอบทุก Role ด้วย `kubectl auth can-i` ก่อนนำไปใช้
8. ควรเก็บ Manifest RBAC ใน Git และให้เปลี่ยนแปลงผ่าน Pull Request เพื่อให้ Audit ย้อนหลังได้
