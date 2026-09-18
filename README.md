# Zenvest — Financial Clarity

A comprehensive wealth management and investment advisory platform comprising a high-performance **FastAPI backend** and a multi-platform **Flutter frontend**.

---

## 📁 Repository Structure

```
Zenvest/
├── backend/              # FastAPI Python backend (REST & WebSocket APIs)
│   ├── app/              # Models, Routers, Services, Middleware
│   ├── seed_data.py      # Database seeder script
│   └── requirements.txt  # Python dependencies
│
└── financial_clarity/    # Flutter cross-platform client app
    ├── lib/              # Riverpod state management, features, routing
    ├── android/          # Android platform configuration
    ├── ios/              # iOS platform configuration
    ├── web/              # Web platform configuration
    └── pubspec.yaml      # Flutter dependencies
```

---

## 🚀 Getting Started

### 1. Backend Service (FastAPI)

```bash
cd backend

# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Start the API server
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

- **API Base URL**: `http://127.0.0.1:8000`
- **Interactive Swagger Docs**: `http://127.0.0.1:8000/docs`
- **ReDoc Documentation**: `http://127.0.0.1:8000/redoc`

### 2. Frontend Client (Flutter)

```bash
cd financial_clarity

# Fetch dependencies
flutter pub get

# Run on Chrome (Web)
flutter run -d chrome --web-port 8080

# Or run on macOS / mobile emulator
flutter run -d macos
```

---

## ✨ Features

- **Portfolio & Budget Tracking**: Real-time asset bifurcation, expense categorization, and net-worth analytics.
- **Mutual Funds Directory & Comparison**: Comprehensive mutual fund analytics with Sharpe ratios, alpha/beta, CAGR, and side-by-side fund comparison.
- **Dual-Consent WebRTC Calling & Chat**: Direct investor-advisor consultation with WebRTC signaling transport.
- **Account Aggregator Integration**: Financial Data Access via Consent Manager / AA protocols.
- **SEBI / ARN Compliance & Verification**: Dedicated advisor onboarding flow with ARN document verification.
