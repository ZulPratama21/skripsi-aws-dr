# Status audit EC2-only (per 21 Oktober 2026)

Status di bawah membedakan implementasi dalam **kode** dari penerapan/hasil uji **AWS**. Tidak ada AWS perubahan yang dieksekusi dalam penyusunan paket.

| Komponen | Di dalam patch | Bukti live yang masih diperlukan |
|---|---|---|
| Tidak memakai EKS | `Region-A/main.tf` bebas EKS, 1 EC2 primary | `terraform plan` menampilkan EKS/node group/ELB yang lama diterminasi dengan aman, lalu inventory AWS |
| EC2 Region B stopped standby | GitHub workflow melakukan `ec2 start-instances` + wait | EC2 state STOPPED sebelum setiap trial; RUNNING saat recovery |
| Manual vs otomatis | `workflow_dispatch` vs `repository_dispatch`, **job identik** | GitHub run log + AWS EventBridge invocation untuk atribusi trigger |
| CloudWatch HealthCheck | Health check `/healthz` pada IPv4 EC2 A, CloudWatch di us-east-1 | Alarm history OK->ALARM->OK |
| DNS failover | Record Route 53 PRIMARY / SECONDARY opsional | Set hosted zone/FQDN, uji DNS dan HTTP dari luar AWS |
| Validasi HTTP Region B | Ansible + `scripts/verify_dr.py` | Artifact `region-b-direct.json` dan opsional `region-b-dns.json` |
| Keamanan SSH | SSH temporary /32 lewat GitHub OIDC | Periksa Security Group tidak membuka port 22 permanen; review IAM roles |
| Aplikasi setara A/B | Satu source `Region-A/app/index.html` dipakai EC2 A & Ansible B | Bandingkan body HTTP & `X-DR-Region` |
| Terraform provisioning saat recovery | Tidak dilakukan; IaC untuk persiapan laboratorium | Sesuai desain stopped standby, jangan klaim just-in-time provisioning |
| Simulasi regional outage | Simulasi instance/HTTP fault pada Region A | Jangan klaim seluruh Region AWS pernah down |
| Cost & RTO | Metodologi baru tertulis di `docs/RESEARCH_PROTOCOL.md` | Ambil data baru dan update AWS Pricing Calculator |

## Pemeriksaan otomatis yang dilakukan pada paket lokal
- YAML berhasil diparse dengan PyYAML.
- Python `scripts/verify_dr.py` berhasil lulus pengujian lokal untuk HTTP 200 + header Region B + marker konten aplikasi.
- `terraform fmt -recursive` dan `terraform validate` berhasil untuk Region A dan Region B pada 21 Oktober 2026 (Terraform CLI v1.16.4). Dependency lock file juga dibuat untuk kedua region.
- `terraform plan` **belum dijalankan** karena salinan paket ini tidak memiliki backend/state Terraform aktual maupun kredensial/variable laboratorium. Plan harus dibuat pada checkout yang memuat state yang benar agar perubahan EKS lama dapat ditinjau secara aman; jangan memakai plan dari state kosong.
- AWS Terraform apply, AWS EC2 start/stop, GitHub repository_dispatch baru, EventBridge invocation, dan Route 53 DNS failover **belum diuji**.
