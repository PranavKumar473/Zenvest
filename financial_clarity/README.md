Overview & Problem Statement
Over 80% of retail investors struggle with fragmented financial data, generic one-size-fits-all budgeting rules, and a lack of accessible, verified investment advisory services.


Zenvest solves this by providing a unified wealth management ecosystem that transforms raw financial data into personalized, actionable strategies—combining algorithmic budgeting, quantitative fund intelligence, and direct, verified advisor consultations.

The Solution: What I Built
Zenvest bridges the gap between passive portfolio tracking and active wealth growth through four core pillars:

1. Adaptive Behavioral Budgeting Engine:
   - Unlike static budgeters, the engine dynamically blends dynamically blends 4 financial frameworks (50/30/20, 70/20/10, Pay Yourself First, and Zero-Based) weighted against user age groups, 5 income brackets, and a weighted 10-question behavioral risk profiler to establish personalized spending limits across 10 expense categories.

2. Quantitative Mutual Fund Intelligence:
   - A real-time analytics engine that processes daily NAV time series from public financial feeds (mfapi.in) and computes 6 institutional-grade risk/return metrics (Sharpe Ratio, Sortino Ratio, Alpha, Beta, CAGR, and Annualized Volatility) for objective, side-by-side fund comparison.

3. Dual-Consent Advisor Consultation & Telephony:
   - On-demand investor–advisor consultation featuring real-time WebRTC audio/video calling over authenticated WebSockets. Both parties must grant mutual consent before call bridges or portfolio views are initiated.
    - Built on a modular telephony architecture with Twilio voice bridging and local mock fallbacks for testing.

4. Institutional Security & Privacy-First Architecture:
   - Stateless JWT authentication with server-side refresh token rotation, bcrypt password hashing, and granular Role-Based Access Control (RBAC) separating Investor and Advisor capabilities.
   - On-device sensitive storage protected with AES-256-GCM authenticated encryption and biometric app lock.



Technical Architecture & Innovation
- Frontend / Client: Multi-platform Flutter application (Android, iOS, Web, macOS) utilizing Riverpod for reactive state management, GoRouter for deep linking, and FL Chart for high-performance financial visualizations.
- Backend / Microservices: High-concurrency FastAPI (Python) server with 60+ async REST and WebSocket endpoints, backed by structured SQLAlchemy schemas and Alembic migrations.
- Data Optimization: Local SQLite caching layer for historical market NAV feeds, cutting redundant external network requests by over 90% and ensuring sub-100ms response times for portfolio dashboards.
- Real-Time Layer: Full-duplex WebSocket channels handling call signaling, consultation requests, and encrypted investor-advisor chat.


Impact & Market Feasibility
- Financial Literacy to Action: Replaces intimidating financial jargon with behavioral nudges and benchmarked metrics.
- Scalable Architecture: Clean separation of concerns (Routers, Services, Repositories, and Provider Interfaces) ready for multi-region cloud deployment.
- Compliance-Ready: Designed around consent-driven financial access patterns (compatible with Account Aggregator / SEBI advisor workflows).



Project Links & Codebase
- GitHub Repository: [https://github.com/PranavKumar473/Zenvest](https://github.com/PranavKumar473/Zenvest)
- Tech Stack: Python, FastAPI, Flutter, Dart, Riverpod, SQLAlchemy, SQLite, WebSockets, WebRTC, SciPy, Razorpay, Twilio

