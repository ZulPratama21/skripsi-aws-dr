# Protokol eksperimen komparatif DR: EC2-only

## Fokus pengujian
**Variabel bebas:** jenis pemicu pipeline pemulihan yang sama:
- A: MANUAL = operator memilih `workflow_dispatch`.
- B: OTOMATIS = CloudWatch Alarm -> EventBridge -> `repository_dispatch`.

**Kontrol:** EC2 A sama, EC2 B sama, tipe/AMI/konfigurasi sama, EC2 B pada kondisi `stopped`, NGINX B `disabled`, interval health check dan DNS TTL tetap, workload aplikasi stateless yang sama pada kedua region.

**Variabel terikat utama:** *durasi pemulihan aktual* = T1 - T0, dalam detik (bukan RTO). **RTO** ditetapkan di awal sebagai target eksperimental; sesudah setiap trial laporkan apakah aktual <= RTO.

**Metrik pendukung:** tingkat keberhasilan, min/median/mean, SD, P95 bila sampel cukup, waktu deteksi CloudWatch, waktu boot instance, durasi Ansible, DNS failover, jumlah langkah manusia, dan proyeksi biaya dengan AWS Pricing Calculator.

## Batasan akademik
1. **Tidak ada regional outage AWS yang sesungguhnya.** Skenario adalah simulasi kegagalan instance atau layanan HTTP primary EC2 di Singapore (misalnya `aws ec2 stop-instances` untuk **EC2 laboratorium A**, atau `systemctl stop nginx` bila akses SSM tersedia), lalu pemulihan antardaerah ke EC2 Tokyo.
2. Mode manual bukan operator mengetik perintah instalasi satu per satu; operator hanya **memicu workflow yang identik**. Dengan demikian, klaim perbedaan terutama mengenai *otomatisasi trigger*, bukan perbandingan seluruh operasional manusia vs skrip.
3. Desain EC2 cadangan `stopped` adalah **pre-provisioned stopped standby/cold standby variant**. Tidak perlu menyebutnya AWS Pilot Light murni.
4. Tanpa data transaksi atau replikasi database, **RPO tidak diuji**.
5. Tes sebelumnya memakai EKS; hasil 3x manual vs 3x otomatis **tidak boleh digabungkan langsung** dengan EC2-only untuk kesimpulan komparatif baru.
6. Uji biaya **EC2-only** harus membandingkan konfigurasi aktual EC2 A/B stopped standby dengan skenario alternatif yang didefinisikan jelas, misalnya B always-on. Jangan mengatribusikan selisih biaya arsitektur kepada trigger manual vs otomatis.

## Prosedur untuk setiap trial
1. Verifikasi Primary HTTP 200 dengan `X-DR-Region: region-a` pada subdomain publik yang sama, B stopped. Catat baseline dan AWS state.
2. Jalankan JMeter di **mesin terpisah** selama keseluruhan eksperimen. Request `http://<DR_FQDN>/` dengan frekuensi tetap, tanpa HTTP cache; simpan hasil mentah JTL/CSV timestamp milidetik, sukses/gagal dan header wilayah.
3. Pada waktu tercatat, injeksikan kegagalan layanan di A (contoh `sudo systemctl stop nginx` pada EC2 A), catat `T_inject` UTC dengan NTP akurat. Kegagalan tersebut bukan pemadaman AWS Region.
4. Manual: operator segera menekan `Run workflow`; otomatis: tunggu CloudWatch ALARM EventBridge memanggil GitHub. Dokumentasikan delay operator sebagai bagian dari eksperimen, jangan sisihkan dari total downtime.
5. Pipeline menyalakan EC2 B (AWS EC2 StartInstances), menunggu health EC2, membuka SSH sementara, menjalankan Ansible, mengecek respons B langsung, lalu opsi memverifikasi endpoint domain DR.
6. Definisikan T0 = awal gangguan layanan berdasarkan probe eksternal (atau waktu injeksi, bila dipilih secara konsisten untuk semua trial). T1 = awal **3 respons HTTP 200 berturut-turut** pada **FQDN yang sama**, dengan `X-DR-Region: region-b` dan konten aplikasi yang benar. Sampling gap turut membatasi presisi.
7. Simpan JMeter raw log, CloudWatch alarm history, EventBridge API Destination Invocations/FailedInvocations, GitHub Action run ID dan artifact, Ansible output, pengamatan DNS, serta output EC2 state. Siapkan rerun reset sampai baseline sama.
8. Ulangi percobaan secara bergantian/acak antarmetode untuk mengurangi bias urutan, dan lakukan cukup replikasi untuk analisis statistik sesuai daya uji yang dibutuhkan; nilai n=3 sebelumnya hanya deskriptif awal.

## Hasil eksperimen yang benar
- Pelaporan utama: mean durasi pemulihan + penyebaran/interval ketidakpastian dan fraksi yang memenuhi RTO target.
- Kesimpulan lebih baik jika waktu aktual lebih pendek secara konsisten tanpa turunnya recovery success rate, dipertanggungjawabkan statistik dan dengan biaya yang dihitung pada basis arsitektur sebanding.
- Lampirkan log dan hash commit/versi konfigurasi untuk reproducibility.

## Evidence minimum
| Evidence | Sumber | Target validasi |
|---|---|---|
| Kondisi awal dan status A/B | EC2 describe-instances / HTTP | A serving; B stopped |
| Alarm kondisi ALARM | CloudWatch alarm history | Kegagalan A terdeteksi |
| Pemanggilan GitHub | EventBridge + GitHub repository_dispatch | Asal trigger otomatis terbukti |
| Boot EC2 B | GitHub artifact start-instance.json, EC2 status | Secondary started by pipeline |
| NGINX B siap | Ansible recap, region-b-direct.json | Respons HTTP yang benar |
| DNS switching | DNS record + region-b-dns.json, JMeter | Satu FQDN pulih di Tokyo |
| Durasi sesungguhnya | JMeter raw JTL/CSV | T0 dan T1 objektif |
| Analisis biaya | AWS Pricing Calculator baru | Besaran dan asumsi transparan |
