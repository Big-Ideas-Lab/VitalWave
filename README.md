# VitalWave: An Open-Source Platform for High-Frequency Physiological Monitoring

**VitalWave** is an open-source, end-to-end system for capturing, processing, and visualizing high-resolution physiological signals from wearable sensors. Designed for digital biomarker development, VitalWave enables cost-efficient, extensible, and research-ready data collection and analysis.

This repository contains the full codebase and design assets, including firmware, hardware schematics, mobile and web applications, and cloud processing pipelines.

---

## Features

- 🧠 **Multimodal Wearable Hardware**  
  Capture high-frequency PPG, accelerometer, and gyroscope signals with a low-cost, custom-designed wearable.

- 📱 **iOS App**  
  Stream sensor data in real-time via BLE, annotate events, and upload securely to the cloud.

- ☁️ **Cloud Infrastructure**  
  Automatically ingest, process, and store incoming data with support for digital biomarker extraction.

- 🌐 **Web Dashboard**  
  Visualize data, manage users and sessions, and monitor device/system status remotely.

- 🔧 **Modular & Open**  
  Designed for extensibility—hardware can be adapted, and the software stack supports additional sensors or analytics modules.

---

## Repository Structure
```text
vitalwave/
├── hardware/ # PCB design files and 3D-printed case models
├── firmware/ # Microcontroller code for wearable sensors
├── ios_app/ # Swift-based iOS app for data acquisition
├── cloud_pipeline/ # Scripts for ingesting and processing data in the cloud
├── web_dashboard/ # React or Flask-based interface for visualizing and managing data
└── docs/ # Documentation, usage guides, and publication references
```
---
## What you need to start
- an assembled watch, or the components listed in the watch assembly guide.
- A Mac with Xcode installed.
- An iPhone and an Apple account.
- Access to the lab’s Firebase project, or your own Firebase project.
- A computer to run the web app.

---
## Setup guides

Follow the guides in order. Each PDF includes step-by-step instructions.

**Already have an assembled and programmed lab watch? Start with Guide 3.**

Current firmware source and build instructions: [firmware/vitalwave_v0](firmware/vitalwave_v0/README.md).


| Step | Guide | What it covers |
|------|-------|----------------|
| 1 | [Install the firmware](docs/01-firmware-setup.pdf) | Programming the PCB and checking that it starts correctly before final watch assembly. |
| 2 | [Assemble the watch](docs/02-watch-assembly.pdf) | Required components, installing the programmed PCB, and final assembly checks. |
| 3 | [Set up Firebase](docs/03-firebase-setup.pdf) | Configuring your own project. |
| 4 | [Install the iOS app](docs/04-ios-setup.pdf) | Configure and installing the app through Xcode using a free Apple account. |
| 5 | [Launch the web app](docs/05-web-app-setup.pdf) | Installing dependencies, configuring Firebase access, and starting the dashboard. |
| 6 | [Make your first recording](docs/06-first-recording.pdf) | Connecting the watch, recording a session, saving data, and exporting a CSV. |

---
## Setup notes
- **iOS app**: When installed through Xcode using a free Apple account, the app’s signing profile expires after seven days. Rebuild and reinstall the app through Xcode to continue using it.

- **Firebase**: Use the free Spark plan for sign-in and session metadata within its usage limits. Uploading recording files through Cloud Storage requires the Blaze pay-as-you-go plan, which includes no-cost allowances. Local CSV export does not require Blaze.

- **At-home studies**: Giving watches to participants for extended use requires additional planning for app distribution, recording reliability, data access, and participant support.

---
## Work in progress 
VitalWave is under active development. 

- **Cardio metrics**: Heart rate (HR), oxygen saturation (SpO₂), and other derived metrics still require further development and validation. They should not be treated as clinically validated measurements.

- **Long-term and remote use**: Reliability for extended recordings and unsupervised use at home is still being evaluated. The current setup is intended for development and research testing. 
