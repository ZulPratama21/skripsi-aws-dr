# Migrasi dari EKS ke EC2-only dengan biaya minimum

## Ruang lingkup
- Region A (Singapore `ap-southeast-1`): **EC2 t3.micro berjalan**, Ubuntu 22.04 + NGINX aplikasi stateless. Tidak ada EKS, node group, Kubernetes, maupun load balancer.
- Region B (Tokyo `ap-northeast-1`): **EC2 t3.micro dibuat terlebih dahulu** tetapi **STOPPED ketika tidak sedang diuji**. Disk EBS dan Elastic IP tetap tersimpan; komputasi EC2 tidak ditagih saat instance berhenti.
- Terraform: membuat resources sebelum eksperimen; tidak dijalankan ketika pemulihan.
- GitHub Actions: menerima `workflow_dispatch` (manusia) atau `repository_dispatch` (EventBridge) lalu **menyalakan EC2 B**, menjalankan Ansible, dan memvalidasi layanan.
- Route 53/CloudWatch/EventBridge: memantau layanan A; DNS failover publik **opsional** sampai zona DNS lab tersedia.
- Strategi: **pre-provisioned stopped standby (varian cold standby)**, BUKAN "Pilot Light tanpa biaya" atau "EKS-to-EKS".

## SEBELUM MENGUBAH INFRASTRUKTUR
1. Simpan salinan state Terraform `Region-A/terraform.tfstate`, `Region-B/terraform.tfstate` (atau remote backend aktual), keduanya rahasia. Jangan pindah ke backend kosong tanpa prosedur state migration.
2. Kode Region A sengaja **menghapus** `aws_eks_cluster.primary_eks`, `aws_eks_node_group.node_group_a`, IAM role EKS, dan subnet kedua dari konfigurasi. Selain itu instance primary lama (`aws_instance.web_server`) diganti dengan resource baru (`aws_instance.primary_ec2`) agar `user_data` konfigurasi HTTP benar-benar berjalan pada first boot. Pastikan EC2 lama tidak berisi data penting. Setelah kode diterapkan, **terraform plan akan mengusulkan destroy**. Ini merupakan konsekuensi perubahan yang diminta; cek apakah EKS masih memiliki workload/data lain. Jangan apply sebelum menerima daftar destroy.
3. **Hapus terlebih dahulu objek Kubernetes** termasuk Service tipe LoadBalancer agar tidak meninggalkan ELB orphan yang masih ditagih (dengan kubeconfig yang benar): `kubectl delete -f Region-A/k8s/app-deployment.yaml` jika objek pernah dibuat; lalu cek AWS Load Balancer dan Target Groups. Jangan menghapus deployment sistem lain. Setelah selesai, hapus source manifest dari repository: `git rm -r Region-A/k8s`.
4. Apabila Anda ingin mempertahankan bukti eksperimen lama, simpan screenshot, histori, dan output AWS di luar repository sebelum migrasi. BAB IV lama tidak otomatis berlaku setelah topologi berubah.
5. Periksa izin dan tagihan dengan AWS Billing Budgets; beberapa komponen Route 53, EBS, SQS, dan IPv4 tetap menimbulkan biaya.

## APPLY yang aman (jangan jalankan tanpa review)
```bash
# Jalankan pada checkout Git yang memuat state/backend yang benar.
terraform -chdir=Region-A init
terraform -chdir=Region-A fmt
terraform -chdir=Region-A validate
terraform -chdir=Region-A plan -out=region-a.tfplan
terraform -chdir=Region-A show region-a.tfplan
# Periksa EKS, role, subnet, EC2 user_data, EIP dan Route 53 sebelum apply.
# terraform -chdir=Region-A apply region-a.tfplan

terraform -chdir=Region-B init
terraform -chdir=Region-B fmt
terraform -chdir=Region-B validate
terraform -chdir=Region-B plan -out=region-b.tfplan
terraform -chdir=Region-B show region-b.tfplan
# Pastikan perubahan user_data/instance tidak mengganti instance tanpa disadari.
# terraform -chdir=Region-B apply region-b.tfplan
```

## Urutan aktivasi laboratorium baru
1. Setelah deployment baru stabil, pastikan EC2 A benar-benar menyajikan `http://<REGION_A_EIP>/` dan `/healthz` dengan header `X-DR-Region: region-a`.
2. EC2 B pertama kali harus BOOT sampai paket NGINX selesai terinstal. Lakukan satu kali pengecekan via SSH/SSM. Pastikan `systemctl is-enabled nginx` memberi `disabled` dan layanan berhenti. **Apabila ini merupakan EC2 lama, `user_data` baru mungkin tidak dieksekusi; nonaktifkan NGINX secara manual satu kali sebelum stop:** `sudo systemctl disable --now nginx`.
3. Stop EC2 B (pastikan memilih instance ID Tokyo yang benar). Tunggu hingga state `stopped`. **Jangan** menghentikan EC2 A, sebab ini primary baseline.
4. Isi secret GitHub Environment `dr-lab`:
   - `AWS_DR_ROLE_ARN`: output Terraform B `github_dr_role_arn` (set `TF_VAR_github_oidc_provider_arn` bila IAM OIDC provider GitHub sudah ada).
   - `EC2_INSTANCE_ID_B`: output `region_b_instance_id`.
   - `EC2_SECURITY_GROUP_ID_B`: output `region_b_security_group_id`.
   - `EC2_HOST_REGION_B`: output `region_b_eip` (IP, tanpa skema http).
   - `ANSIBLE_SSH_KEY`: private key untuk EC2 B, jangan unggah ke Git/repo.
   - `ANSIBLE_KNOWN_HOSTS`: host key EC2 B yang sudah diverifikasi, bukan hasil ssh-keyscan yang belum diverifikasi.
5. Setelah endpoint primary sehat dan konfigurasi GitHub/OIDC disiapkan, aktifkan pemicu EventBridge hanya untuk pengujian otomatis dengan `TF_VAR_enable_eventbridge_dispatch=true` dan apply Terraform A lagi. Nilai default `false` mencegah alarm saat provisioning memicu DR tanpa disengaja. Untuk mode MANUAL pemicu otomatis boleh dibiarkan `false` (hindari kontaminasi eksperimen).
6. Route 53 failover publik (opsional): gunakan hosted zone lab yang Anda miliki; set `TF_VAR_dr_hosted_zone_id`, `TF_VAR_dr_record_name`, `TF_VAR_secondary_eip` dari Region B dan `TF_VAR_enable_dns_failover=true` di Terraform A. `TF_VAR_github_pat` masih dibutuhkan untuk EventBridge API Destination. GitHub Environment variable `DR_FQDN` boleh diisi subdomain sama untuk memvalidasi end-to-end DNS.
7. Uji lebih dulu mode MANUAL `workflow_dispatch`. Lalu reset secondary `stopped` dan primary sehat sebelum menguji mode OTOMATIS.

## Cara mereset setiap percobaan
1. Kembalikan Primary EC2 A ke HTTP 200 untuk `/healthz` (jangan restart AWS Region).
2. Pastikan NGINX B **disabled** pada boot berikutnya (Ansible sudah memakai `enabled: false`).
3. Stop EC2 B dan tunggu `stopped`:
```bash
aws ec2 stop-instances --region ap-northeast-1 --instance-ids <INSTANCE_ID_B>
aws ec2 wait instance-stopped --region ap-northeast-1 --instance-ids <INSTANCE_ID_B>
```
4. Tunggu Route 53 kembali memberikan primary IP; periksa bahwa `/healthz` di B gagal diakses. Pastikan status CloudWatch menjadi OK dan pengujian punya baseline normal sebelum simulasi dimulai.
5. Untuk simulasi outage lab tanpa membuka SSH pada primary, Anda boleh menghentikan **EC2 instance A saja** dengan `aws ec2 stop-instances --region ap-southeast-1 --instance-ids <INSTANCE_ID_A>` (lihat output `region_a_instance_id`). Pulihkan dengan `aws ec2 start-instances --region ap-southeast-1 --instance-ids <INSTANCE_ID_A>`; NGINX pada A otomatis aktif saat boot. Ini **instance outage**, bukan AWS Regional Outage. Alternatif bila ada akses SSM yang aman, injeksikan gangguan HTTP melalui `sudo systemctl stop nginx` dan pulihkan `sudo systemctl start nginx`. Jangan menjalankan pada workload produksi.

## Estimasi penghematan dan biaya sisa
- Tidak ada biaya EKS control-plane dan tidak ada node EKS maupun ELB dalam arsitektur **baru**. Resources yang tidak dihapus di AWS masih akan ditagih.
- **EC2 B stopped:** komputasi berhenti ditagih, tetapi volume EBS tetap ditagih dan EIP tetap terkena biaya IPv4. `start/stop` menambah waktu pemulihan (uji RTO ulang).
- **EC2 A:** compute, EBS, dan IPv4 sepanjang berjalan.
- AWS menghitung alamat IPv4 publik sekitar **USD 0.005/jam/alamat**, baik attached maupun idle, sehingga 2 alamat selama 730 jam ~ USD 7.30/bulan, di luar EC2/EBS/Route53 dan pajak. Harga dapat berubah menurut wilayah dan waktu; ulangi perhitungan dengan AWS Pricing Calculator.
- Route 53 hosted zone, health check (lebih cepat 10 detik umumnya lebih mahal dari 30 detik), EventBridge, SQS, dan transfer tetap berpotensi memiliki biaya.
- Jangan bandingkan angka biaya EKS lama ($160.65 versus $278.96) dengan laboratorium EC2 baru sebagai hasil eksperimen yang sama; perbarui parameter di AWS Pricing Calculator.

## Keamanan dan batasan
- Terraform `tls_private_key` **legacy** masih disimpan untuk kompatibilitas state & EC2 lama. Keberadaannya di Terraform state adalah risiko: batasi izin state dan rotasi setelah penelitian.
- Github PAT disimpan oleh AWS EventBridge Connection dan bisa tersimpan sensitif dalam Terraform state. Jangan commit `tfstate`, `.tfvars`, `.pem`, atau log yang berisi rahasia.
- Workflow membuka port SSH B hanya sementara untuk IPv4 publik GitHub runner dan menutupnya setelah selesai. Tetap batasi environment dan IAM role.
- Jika EIP/AMI/instance/SSH host key berubah, perbarui GitHub Secrets dan verifikasi host key dari sumber tepercaya.
- **Saya tidak mengeksekusi terraform apply, destroy, atau menyalakan/mematikan instance AWS** dalam penyusunan patch ini. Status aktual AWS harus diperiksa setelah kode diterapkan.
