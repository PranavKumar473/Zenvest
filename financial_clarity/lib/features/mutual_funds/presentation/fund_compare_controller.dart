import 'package:flutter_riverpod/flutter_riverpod.dart';

class FundCompareNotifier extends StateNotifier<List<int>> {
  FundCompareNotifier() : super([]);

  static const int maxCompareLimit = 3;

  void toggle(int schemeCode) {
    if (state.contains(schemeCode)) {
      state = state.where((id) => id != schemeCode).toList();
    } else {
      if (state.length >= maxCompareLimit) {
        // Remove the first selected fund to make space, or do nothing.
        // Let's replace the first one or just not allow adding.
        // Let's do nothing but let the UI show a warning/toast.
        return;
      }
      state = [...state, schemeCode];
    }
  }

  void add(int schemeCode) {
    if (!state.contains(schemeCode) && state.length < maxCompareLimit) {
      state = [...state, schemeCode];
    }
  }

  void remove(int schemeCode) {
    state = state.where((id) => id != schemeCode).toList();
  }

  void clear() {
    state = [];
  }
}

final fundCompareProvider =
    StateNotifierProvider<FundCompareNotifier, List<int>>((ref) {
  return FundCompareNotifier();
});
