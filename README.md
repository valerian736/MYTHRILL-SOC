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

## Tim

| Nama                       | Peran                     | Kontak                      |
| -------------------------- | ------------------------- | --------------------------- |
| **Valerian Shean Tenedy**  | Desain RTL, integrasi SoC | valerian.tenedy@binus.ac.id |
| **Ryan Reagan Dharmajaya** | Verifikasi, testbench     | ryan.dharmajaya@binus.ac.id |

**Dosen Pembimbing**: Daniel Patricko Gemeno Hutabarat, S.T., M.T. — Universitas Bina Nusantara

---

## Resource Utilization

### Cyclone V SE (DE10-Nano target)

| Resource         | Usage     | Capacity      | %     |
| ---------------- | --------- | ------------- | ----- |
| ALM              | 23,688    | 41,910        | 57 %  |
| Register (FF)    | 37,332    | 41,915        | 89 %  |
| Block RAM (M10K) | 2,048 bit | 5,662,720 bit | < 1 % |
| DSP Block        | 30        | 112           | 27 %  |
| Pin              | 18        | 314           | 6 %   |

---

## Daftar Isi

- [Arsitektur Sistem](#arsitektur-sistem)
- [Fitur Utama](#fitur-utama)
- [Blok MLP](#blok-mlp)
- [Struktur Repository](#struktur-repository)
- [Cara Build & Jalankan](#cara-build--jalankan)
- [Hasil Verifikasi](#hasil-verifikasi)

---

## Arsitektur Sistem

![Arsitektur SoC](imgs/BLOCK%20DIAGRAM.png)

**Alur data**: Sensor → Scaler (normalisasi Q16.16) → MLP → CPU (mapping ke PWM) → ESC → Thruster.

### Komponen Utama

| Blok                       | Fungsi                                                       |
| -------------------------- | ------------------------------------------------------------ |
| **PicoRV32**               | CPU soft-core RISC-V RV32IM, AXI4-Lite master                |
| **ROM / SRAM**             | Memori program (BRAM) dan data                               |
| **AXI4-Lite Interconnect** | Crossbar untuk semua periferal (6 slave)                     |
| **MLP Block**              | Akselerator neural network 5→4→4→1, dengan scaler built-in   |
| **Sensor Controller**      | Aggregator untuk RS485 (SEM228A, SN300) dan I2C (AHT10, RTC) |
| **PWM**                    | Output untuk ESC (thruster BLDC)                             |
| **UART**                   | Debug host, 115200 baud                                      |
| **Security**               | Range check + watchdog pada jalur kritis                     |

### Peta Alamat

| Modul             | Alamat                        |
| ----------------- | ----------------------------- |
| Program (BRAM)    | `0x0000_0000` – `0x0000_FFFF` |
| SRAM              | `0x1000_0000` – `0x1000_FFFF` |
| PWM               | `0x2000_0000` – `0x2000_FFFF` |
| UART              | `0x3000_0000` – `0x3000_FFFF` |
| MLP               | `0x4000_0000` – `0x4000_FFFF` |
| Sensor Controller | `0x5000_0000` – `0x5000_FFFF` |

---

## Fitur Utama

### 1. Akselerator MLP Hardware

![Arsitektur MLP](imgs/BLOCK%20DIAGRAM%20MLP.png)

- Arsitektur **5 → 4 (ReLU) → 4 (ReLU) → 1 (linear)**
- Format fixed-point **Q16.16** (32-bit, 16 bit fraksi)
- Bobot dan bias tersimpan permanen sebagai konstanta ROM (tanpa file I/O saat sintesis)
- Akumulator 64-bit dengan saturasi hardware
- Inferensi deterministik, **< 120 siklus clock**
- **Serializer** antar lapisan mem-pipeline keluaran satu lapisan ke lapisan berikutnya pada setiap siklus clock

### 2. SoC Lengkap dengan PicoRV32

- CPU soft-core **RISC-V RV32IM** (dengan MUL/DIV hardware)
- Interkoneksi **AXI4-Lite** untuk semua periferal
- Firmware C ringan (bare-metal) untuk polling sensor, trigger MLP, dan update PWM

### 3. Kontroler Sensor Multi-Protokol

![Kontroler Sensor](imgs/BLOCK%20DIAGRAM%20SENSOR.png)

- **RS485 (Modbus RTU)** untuk SEM228A (iradiansi) dan SN300 (anemometer), dengan verifikasi CRC16
- **I2C** untuk AHT10 (suhu/kelembapan) dan DS3231 (RTC)
- Output sensor langsung ke MLP tanpa melewati CPU (jalur hardware langsung)

### 4. Pipeline Sensor (Sinkronisasi Data)

![Pipeline Sensor](imgs/BLOCK%20DIAGRAM%20PIPELINE.png)

Setiap nilai sensor melewati **shift register 3 tahap**. Tujuannya agar sinyal `data` dan `valid` tetap sinkron saat mencapai blok MLP — mengatasi delay kombinasional yang berbeda antara jalur RS485 dan I2C.



## Blok MLP

### Model

- **Input**: 5 fitur (irradiance, hour, humidity, temperature, wind speed)
- **Hidden layer 1**: 4 neuron, aktivasi ReLU
- **Hidden layer 2**: 4 neuron, aktivasi ReLU
- **Output**: 1 neuron, aktivasi linear
- **Total parameter**: 49 (Q16.16, hardcoded di ROM)

### Register Periferal MLP

| Register        | Alamat        | Akses | Keterangan                             |
| --------------- | ------------- | ----- | -------------------------------------- |
| `MLP_RDY`       | `0x00`        | r     | bit0 = 1 jika hasil valid              |
| `MLP_OUT`       | `0x04`        | r     | prediksi terakhir (Q16.16)             |
| `MLP_TRG`       | `0x08`        | w     | tulis bit0 = 1 untuk memulai inferensi |
| `MLP_INT`       | `0x0C`        | rw    | interval auto-start (clock)            |
| `FEAT0`–`FEAT4` | `0x10`–`0x20` | rw    | fitur manual (jika `MLP_SRC=0`)        |
| `MLP_SRC`       | `0x24`        | rw    | 1 = sensor bridge, 0 = FEAT regs       |

### Verifikasi Numerik

Model Q16.16 dibandingkan dengan Keras floating-point:

```
Input: [80 W/m², jam 12, 95 % RH, 24 °C, 10.5 km/h]
Keras: 1.2483971 mm/h
Fixed: 1.2483673 mm/h
Diff:  0.00003 mm/h  (< 0.003%)
```

Testbench menguji **100 vektor** dari dataset:

```
vectors run: 100 | mismatches: 0 | timeouts: 0 | worst diff: 0 LSB (tol 2)
PASS
```

## Hasil Verifikasi

### 1. Verifikasi RTL vs Keras (100 vektor)

```
vectors run: 100 | mismatches: 0 | timeouts: 0 | worst diff: 0 LSB (tol 2)
PASS
```

### 2. Demo Hardware (Gowin GW2AR-18 / Tang Nano 20K)

![live output dari putty](<imgs/live inference.png>)

pengetesan pada hardware FPGA tang nano 20k untuk mengeluarkan hasil inferensi dengan nilai tetap.Input tetap `{80 W/m², 12, 95 %, 24 °C, 10.5 km/h}` menghasilkan prediksi **1.306 mm/h**, konsisten dengan hasil fixed-point notebook (1.248 mm/h) dalam toleransi < 5 %.

### 3. Sintesis Quartus Prime

```
Quartus Prime 25.1std.0 Lite Edition
Device: 5CSEBA6U23C7 (Cyclone V SE)
Status: Successful — 0 errors

Logic utilization (in ALMs) : 23,688 / 41,910 (57 %)
Total registers             : 37,332
Total block memory bits     : 2,048 / 5,662,720 (< 1 %)
Total DSP blocks            : 30 / 112 (27 %)
Total pins                  : 18 / 314 (6 %)
```


## Cara Build & Jalankan

### Kompilasi Firmware

kompilasi firmware dijanlan melalui linux wsl subsystem pada windows dengan toolchain-riscv

```makefile

CROSS ?= $(shell command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 && echo riscv64-unknown-elf- || echo riscv64-linux-gnu-)
DELAY ?= 2000000
WORDS ?= 1024     

CFLAGS = -march=rv32imc_zicsr -mabi=ilp32 -O1 \
         -ffreestanding -nostdlib -static -fno-pie -no-pie \
         -fno-asynchronous-unwind-tables -fno-unwind-tables \
         -Wall -DDELAY=$(DELAY)
LDFLAGS = -T link.ld -Wl,-melf32lriscv -Wl,--gc-sections

all: firmware.hex
	$(CROSS)size firmware.elf

firmware.elf: start.S main.c link.ld
	$(CROSS)gcc $(CFLAGS) $(LDFLAGS) -o $@ start.S main.c

firmware.bin: firmware.elf
	$(CROSS)objcopy -O binary $< $@

firmware.hex: firmware.bin makehex.py
	python3 makehex.py $< $(WORDS) > $@

clean:
	rm -f firmware.elf firmware.bin firmware.hex

.PHONY: all clean
```

---





