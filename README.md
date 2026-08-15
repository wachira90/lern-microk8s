# Lerning microk8s

**CIS Benchmark (อ้างอิงหมวด Network & Firewall ของ Ubuntu Linux)** 

ที่สคริปต์นี้ทำการ "Patch" (ปรับเปลี่ยนชั่วคราว) เพื่อให้ MicroK8s ทำงานได้ และการคืนค่าเมื่อสั่งยกเลิก

| หมวดหมู่ CIS Benchmark / ข้อกำหนด | มาตรฐาน CIS (Hardening) บังคับใช้อะไร? | ทำไม MicroK8s ถึงต้องแก้? (Impact) | เมื่อรันสคริปต์โหมด `enable` | เมื่อรันสคริปต์โหมด `disable` |
| --- | --- | --- | --- | --- |
| **3.1.1 Ensure IP forwarding is disabled** | บังคับ `net.ipv4.ip_forward = 0` เพื่อไม่ให้เซิร์ฟเวอร์ทำตัวเป็น Router | หากปิด Pods ใน Kubernetes จะไม่สามารถสื่อสารข้าม Node หรือออกอินเทอร์เน็ตได้เลย | บังคับค่าเป็น `1` | คืนค่ากลับเป็น `0` |
| **Network & Kernel (Bridge Netfilter)** | ระบบที่ปลอดภัยมักจะไม่โหลดโมดูลที่ไม่จำเป็นหรือปล่อยให้ iptables มองเห็น Bridge | CNI Plugins (เช่น Calico/Flannel) ต้องใช้ iptables ควบคุม Network Policy บน Bridge ของ Container | กำหนดค่า `bridge-nf-call-iptables = 1` และโหลดโมดูล `br_netfilter` | คืนค่ากลับเป็น `0` |
| **3.5.x Ensure default deny firewall policy** | นโยบายทราฟฟิกที่วิ่งผ่าน (Routed/Forward) บน UFW ต้องเป็น `drop` หรือ `deny` เป็นค่าเริ่มต้น | ทราฟฟิกของ Container จะวิ่งผ่านเครื่องไม่ได้ และถูก Drop ทิ้งทันที | ตั้งค่า `ufw default allow routed` | คืนค่าเป็น `ufw default drop routed` |
| **3.5.x Ensure firewall rules exist for all open ports** | บล็อกทราฟฟิกขาเข้า/ขาออกทั้งหมด และไม่อนุญาต Interface ที่ไม่รู้จัก | MicroK8s สร้าง Virtual Interfaces ขึ้นมาเอง (`cni0`, `cali+`, ฯลฯ) ซึ่งจะถูก UFW บล็อก | เปิด Allow เข้า-ออก ให้ Interfaces ของ CNI โดยเฉพาะ | ลบ (Delete) กฎ Allow ของ Interfaces เหล่านี้ทิ้ง |
| **3.5.x Ensure loopback / specific traffic is configured** | อนุญาตเฉพาะพอร์ตบริการหลักที่จำเป็น (เช่น SSH 22, HTTP 80/443) | K8s Components (API, Kubelet, Dqlite) ต้องใช้พอร์ตเฉพาะคุยกันเองภายในคลัสเตอร์ | เปิด Allow พอร์ต (เช่น 16443, 10250, 25000) | ลบ (Delete) กฎ Allow พอร์ตเหล่านี้ทิ้ง |

**สรุปการทำงาน:**
สคริปต์นี้ไม่ได้ยกเลิก CIS Hardening ทั้งระบบ แต่เข้าไป **"เจาะช่องเฉพาะจุดที่จำเป็น" (Whitelist)** ในหมวดของ Network Sysctl และ UFW Firewall เพื่อให้ CNI (Container Network Interface) ของ MicroK8s หายใจได้ ส่วนเรื่องความปลอดภัยอื่นๆ เช่น SSH, File Permissions หรือ Auditing จะยังคงมีความเข้มงวดตามที่คุณได้ Hardening ไว้ 100% ปกติ

```sh
./microk8s-cis-patch.sh enable

./microk8s-cis-patch.sh disable
```
