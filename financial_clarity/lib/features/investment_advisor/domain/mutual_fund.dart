/// Mutual fund domain models — mirror backend mutual_fund_service.py.
/// All fields here are real, computed from AMFI-linked NAV history
/// (mfapi.in). Deliberately no expense ratio / AUM / manager / holdings
/// fields — those aren't available from free public data and are not
/// fabricated.

class FundNavPoint {
  final DateTime date;
  final double nav;

  const FundNavPoint({required this.date, required this.nav});

  factory FundNavPoint.fromJson(Map<String, dynamic> json) {
    return FundNavPoint(
      date: DateTime.parse(json['date'] as String),
      nav: (json['nav'] as num).toDouble(),
    );
  }
}

class FundYearlyReturn {
  final int year;
  final double returnPct;

  const FundYearlyReturn({required this.year, required this.returnPct});

  factory FundYearlyReturn.fromJson(Map<String, dynamic> json) {
    return FundYearlyReturn(
      year: json['year'] as int,
      returnPct: (json['return_pct'] as num).toDouble(),
    );
  }
}

class MutualFundSummary {
  final int schemeCode;
  final String name;
  final String? fundHouse;
  final String? category;
  final double? nav;
  final double? returns1y;
  final double? returns3y;
  final double? returns5y;
  final String? highlight;

  const MutualFundSummary({
    required this.schemeCode,
    required this.name,
    this.fundHouse,
    this.category,
    this.nav,
    this.returns1y,
    this.returns3y,
    this.returns5y,
    this.highlight,
  });

  factory MutualFundSummary.fromJson(Map<String, dynamic> json) {
    return MutualFundSummary(
      schemeCode: json['scheme_code'] as int,
      name: json['name'] as String? ?? 'Mutual Fund',
      fundHouse: json['fund_house'] as String?,
      category: json['category'] as String?,
      nav: (json['nav'] as num?)?.toDouble(),
      returns1y: (json['returns_1y'] as num?)?.toDouble(),
      returns3y: (json['returns_3y'] as num?)?.toDouble(),
      returns5y: (json['returns_5y'] as num?)?.toDouble(),
      highlight: json['highlight'] as String?,
    );
  }
}

class MutualFundDetail {
  final int schemeCode;
  final String name;
  final String? fundHouse;
  final String? category;
  final String? schemeType;
  final String? isin;
  final double? nav;
  final DateTime? navDate;
  final double? returns1m;
  final double? returns3m;
  final double? returns6m;
  final double? returns1y;
  final double? returns3y;
  final double? returns5y;
  final double? returnsSinceInception;
  final DateTime? inceptionDate;
  final List<FundYearlyReturn> yearlyReturns;
  final List<FundNavPoint> navChart;
  final String? dataSource;

  const MutualFundDetail({
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
    this.returnsSinceInception,
    this.inceptionDate,
    this.yearlyReturns = const [],
    this.navChart = const [],
    this.dataSource,
  });

  factory MutualFundDetail.fromJson(Map<String, dynamic> json) {
    return MutualFundDetail(
      schemeCode: json['scheme_code'] as int,
      name: json['name'] as String? ?? 'Mutual Fund',
      fundHouse: json['fund_house'] as String?,
      category: json['category'] as String?,
      schemeType: json['scheme_type'] as String?,
      isin: json['isin'] as String?,
      nav: (json['nav'] as num?)?.toDouble(),
      navDate: json['nav_date'] != null
          ? DateTime.tryParse(json['nav_date'] as String)
          : null,
      returns1m: (json['returns_1m'] as num?)?.toDouble(),
      returns3m: (json['returns_3m'] as num?)?.toDouble(),
      returns6m: (json['returns_6m'] as num?)?.toDouble(),
      returns1y: (json['returns_1y'] as num?)?.toDouble(),
      returns3y: (json['returns_3y'] as num?)?.toDouble(),
      returns5y: (json['returns_5y'] as num?)?.toDouble(),
      returnsSinceInception:
          (json['returns_since_inception'] as num?)?.toDouble(),
      inceptionDate: json['inception_date'] != null
          ? DateTime.tryParse(json['inception_date'] as String)
          : null,
      yearlyReturns: (json['yearly_returns'] as List? ?? [])
          .map((e) => FundYearlyReturn.fromJson(e as Map<String, dynamic>))
          .toList(),
      navChart: (json['nav_chart'] as List? ?? [])
          .map((e) => FundNavPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      dataSource: json['data_source'] as String?,
    );
  }
}
