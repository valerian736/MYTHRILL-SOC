# MYTHRILL-SOC

**SoC berbasis RISC-V dengan Akselerator MLP untuk Prediksi Curah Hujan pada Sistem Propulsi Cerdas USV Tenaga Surya**

[![Hackathon](https://img.shields.io/badge/PERURI%20Chip%20Hackathon-2026-blue)](https://peruri.co.id)
[![Track](https://img.shields.io/badge/Track-03%20AI%20%2F%20Edge%20Accelerator-green)]()
[![FPGA](https://img.shields.io/badge/FPGA-Cyclone%20V%20%7C%20GW2AR--18-orange)]()
[![Status](https://img.shields.io/badge/status-working%20prototype-brightgreen)]()

---

## Kata Pengantar

Repository ini adalah submission tim **MYTHRILL** untuk **PERURI Chip Hackathon 2026**, kategori **03 – AI / Edge Accelerator**.

Sistem yang dirancang adalah sebuah **System-on-Chip (SoC) berbasis RISC-V** dengan **akselerator Multilayer Perceptron (MLP)** khusus untuk memprediksi laju presipitasi (curah hujan) secara real-time dari lima fitur sensor: iradiansi surya, jam, kelembapan, suhu, dan kecepatan angin. Prediksi kemudian dipetakan ke sinyal PWM yang mengendalikan kecepatan thruster USV, sehingga konsumsi daya propulsi menyesuaikan kondisi cuaca tanpa memerlukan SBC eksternal.

**Status**: RTL telah disintesis pada **dua toolchain berbeda** (Gowin dan Intel Quartus Prime) dan **didemonstrasikan pada board FPGA Gowin GW2AR-18 (Tang Nano 20K)**, menghasilkan prediksi `Rain = 1.306 mm/h` untuk input sensor tetap, dengan output PWM yang sesuai. Verifikasi numerik menunjukkan **0 LSB error** terhadap model floating-point Keras pada 100 vektor uji.

---

## Daftar Isi

- [Arsitektur Sistem](#arsitektur-sistem)
- [Fitur Utama](#fitur-utama)
- [Blok MLP](#blok-mlp)
- [Struktur Repository](#struktur-repository)
- [Cara Build & Jalankan](#cara-build--jalankan)
- [Hasil Verifikasi](#hasil-verifikasi)
- [Resource Utilization](#resource-utilization)
- [Tim](#tim)
- [Referensi](#referensi)

---

## Arsitektur Sistem

