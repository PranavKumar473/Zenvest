/// Mutual fund domain models — mirror backend responses from
/// GET /mutual-funds/directory, /top5, /{scheme_code}
/// (see backend/app/services/mutual_fund_service.py, risk_metrics_service.py).
/// All fields sourced from mfapi.in (AMFI-linked NAV registry) + NSE index
/// data for risk metrics. Fields with no free/licensed data source (AUM,
/// expense ratio, sector allocation, fund manager) are surfaced via
/// [FundDetail.unavailableFields] rather than fabricated.

class FundSummary {
  final int schemeCode;
  final String name;
  final String? fundHouse;
  final double? nav;
  final double? returns1y;
  final double? returns3y;

  const FundSummary({
    required this.schemeCode,
    required this.name,
    this.fundHouse,
    this.nav,
    this.returns1y,
    this.returns3y,
  });

  factory FundSummary.fromJson(Map<String, dynamic> json) => FundSummary(
        schemeCode: json['scheme_code'] as int,
        name: json['name'] as String? ?? 'Unnamed Fund',
        fundHouse: json['fund_house'] as String?,
        nav: (json['nav'] as num?)?.toDouble(),
        returns1y: (json['returns_1y'] as num?)?.toDouble(),
        returns3y: (json['returns_3y'] as num?)?.toDouble(),
      );
}

class FundCategory {
  final String category;
  final List<FundSummary> funds;

  const FundCategory({required this.category, required this.funds});

  factory FundCategory.fromJson(Map<String, dynamic> json) => FundCategory(
        category: json['category'] as String,
        funds: (json['funds'] as List? ?? [])
            .map((f) => FundSummary.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}

class TopFund {
  final int schemeCode;
  final String name;
  final String? fundHouse;
  final String? category;
  final double compositeScore;
  final double? returns1y;
  final double? returns3y;
  final double? sharpeRatio;
  final double? sortinoRatio;
  final double? alpha;
  final double? beta;
  final String? rankingBasis;

  const TopFund({
    required this.schemeCode,
    required this.name,
    this.fundHouse,
    this.category,
    required this.compositeScore,
    this.returns1y,
    this.returns3y,
    this.sharpeRatio,
    this.sortinoRatio,
    this.alpha,
    this.beta,
    this.rankingBasis,
  });

  factory TopFund.fromJson(Map<String, dynamic> json) => TopFund(
        schemeCode: json['scheme_code'] as int,
        name: json['name'] as String? ?? 'Unnamed Fund',
        fundHouse: json['fund_house'] as String?,
        category: json['category'] as String?,
        compositeScore: (json['composite_score'] as num?)?.toDouble() ?? 0.0,
        returns1y: (json['returns_1y'] as num?)?.toDouble(),
        returns3y: (json['returns_3y'] as num?)?.toDouble(),
        sharpeRatio: (json['sharpe_ratio'] as num?)?.toDouble(),
        sortinoRatio: (json['sortino_ratio'] as num?)?.toDouble(),
        alpha: (json['alpha'] as num?)?.toDouble(),
        beta: (json['beta'] as num?)?.toDouble(),
        rankingBasis: json['ranking_basis'] as String?,
      );
}

class RiskMetrics {
  final double? volatilityAnnualized;
  final double? sharpeRatio;
  final double? sortinoRatio;
  final double? alpha;
  final double? beta;
  final String? benchmarkUsed;

  const RiskMetrics({
    this.volatilityAnnualized,
    this.sharpeRatio,
    this.sortinoRatio,
    this.alpha,
    this.beta,
    this.benchmarkUsed,
  });

  factory RiskMetrics.fromJson(Map<String, dynamic> json) => RiskMetrics(
        volatilityAnnualized: (json['volatility_annualized'] as num?)?.toDouble(),
        sharpeRatio: (json['sharpe_ratio'] as num?)?.toDouble(),
        sortinoRatio: (json['sortino_ratio'] as num?)?.toDouble(),
        alpha: (json['alpha'] as num?)?.toDouble(),
        beta: (json['beta'] as num?)?.toDouble(),
        benchmarkUsed: json['benchmark_used'] as String?,
      );

  bool get hasAnyData =>
      sharpeRatio != null || sortinoRatio != null || alpha != null || beta != null || volatilityAnnualized != null;
}

class YearlyReturn {
  final int year;
  final double returnPct;

  const YearlyReturn({required this.year, required this.returnPct});

  factory YearlyReturn.fromJson(Map<String, dynamic> json) => YearlyReturn(
        year: json['year'] as int,
        returnPct: (json['return_pct'] as num).toDouble(),
      );
}

class NavPoint {
  final DateTime date;
  final double nav;

  const NavPoint({required this.date, required this.nav});

  factory NavPoint.fromJson(Map<String, dynamic> json) => NavPoint(
        date: DateTime.parse(json['date'] as String),
        nav: (json['nav'] as num).toDouble(),
      );
}

class FundDetail {
  final int schemeCode;
  final String name;
  final String? fundHouse;
  final String? category;
  final String? schemeType;
  final String? isin;
  final double? nav;
  final String? navDate;
  final double? returns1m;
  final double? returns3m;
  final double? returns6m;
  final double? returns1y;
  final double? returns3y;
  final double? returns5y;
  final double? returns10y;
  final double? returnsSinceInception;
  final String? inceptionDate;
  final List<YearlyReturn> yearlyReturns;
  final List<NavPoint> navChart;
  final RiskMetrics riskMetrics;
  final List<String> unavailableFields;
  final String? dataSource;

  const FundDetail({
    required this.schemeCode,
    required this.name,
    this.fundHouse,
    this.category,
    this.schemeType,
    this.isin,
    this.nav,
    this.navDate,
    this.returns1m,
    this.returns3m,
    this.returns6m,
    this.returns1y,
    this.returns3y,
    this.returns5y,
    this.returns10y,
    this.returnsSinceInception,
    this.inceptionDate,
    this.yearlyReturns = const [],
    this.navChart = const [],
    this.riskMetrics = const RiskMetrics(),
    this.unavailableFields = const [],
    this.dataSource,
  });

  factory FundDetail.fromJson(Map<String, dynamic> json) => FundDetail(
        schemeCode: json['scheme_code'] as int,
        name: json['name'] as String? ?? 'Unnamed Fund',
        fundHouse: json['fund_house'] as String?,
        category: json['category'] as String?,
        schemeType: json['scheme_type'] as String?,
        isin: json['isin'] as String?,
        nav: (json['nav'] as num?)?.toDouble(),
        navDate: json['nav_date'] as String?,
        returns1m: (json['returns_1m'] as num?)?.toDouble(),
        returns3m: (json['returns_3m'] as num?)?.toDouble(),
        returns6m: (json['returns_6m'] as num?)?.toDouble(),
        returns1y: (json['returns_1y'] as num?)?.toDouble(),
        returns3y: (json['returns_3y'] as num?)?.toDouble(),
        returns5y: (json['returns_5y'] as num?)?.toDouble(),
        returns10y: (json['returns_10y'] as num?)?.toDouble(),
        returnsSinceInception: (json['returns_since_inception'] as num?)?.toDouble(),
        inceptionDate: json['inception_date'] as String?,
        yearlyReturns: (json['yearly_returns'] as List? ?? [])
            .map((e) => YearlyReturn.fromJson(e as Map<String, dynamic>))
            .toList(),
        navChart: (json['nav_chart'] as List? ?? [])
            .map((e) => NavPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        riskMetrics: json['risk_metrics'] != null
            ? RiskMetrics.fromJson(json['risk_metrics'] as Map<String, dynamic>)
            : const RiskMetrics(),
        unavailableFields:
            (json['unavailable_fields'] as List? ?? []).map((e) => e.toString()).toList(),
        dataSource: json['data_source'] as String?,
      );

  bool isUnavailable(String field) => unavailableFields.contains(field);
}

/// Answers the "Who guided your investment?" modal — see
/// backend/app/schemas/investment.py::InvestmentGuidance. The platform's
/// corporate ARN is applied server-side and is never part of this payload.
class InvestmentGuidance {
  final String source; // 'robo' | 'human'
  final String? advisorName;
  final String? advisorEuin;
  final String? advisorId;

  const InvestmentGuidance({
    this.source = 'robo',
    this.advisorName,
    this.advisorEuin,
    this.advisorId,
  });

  Map<String, dynamic> toJson() => {
        'source': source,
        if (advisorName != null) 'advisor_name': advisorName,
        if (advisorEuin != null) 'advisor_euin': advisorEuin,
        if (advisorId != null) 'advisor_id': advisorId,
      };
}
