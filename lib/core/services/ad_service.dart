import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:editaiapp/core/utils/platform_utils.dart';
import '../../features/profile/data/datasources/app_settings_datasource.dart';

/// IDs de teste do AdMob (fallback quando app_settings não retorna valores)
const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';

class AdService {
  final AppSettingsDataSource _appSettings;
  bool _initialized = false;
  InterstitialAd? _interstitialAd;
  bool _isLoadingInterstitial = false;

  AdService(this._appSettings);

  bool get isMobile => !kIsWeb;

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  Future<String> _getBannerAdUnitId() async {
    if (isAndroid) {
      final id = await _appSettings.getValue('admob_banner_android');
      return id ?? _testBannerAndroid;
    }
    if (isIOS) {
      final id = await _appSettings.getValue('admob_banner_ios');
      return id ?? _testBannerIos;
    }
    return _testBannerAndroid;
  }

  Future<String> _getInterstitialAdUnitId() async {
    if (isAndroid) {
      final id = await _appSettings.getValue('admob_interstitial_android');
      return id ?? _testInterstitialAndroid;
    }
    if (isIOS) {
      final id = await _appSettings.getValue('admob_interstitial_ios');
      return id ?? _testInterstitialIos;
    }
    return _testInterstitialAndroid;
  }

  /// Retorna o ad unit ID do banner para a plataforma atual. Null em web.
  Future<String?> getBannerAdUnitId() async {
    if (kIsWeb) return null;
    return _getBannerAdUnitId();
  }

  /// Pré-carrega o intersticial para exibição rápida posterior.
  Future<void> preloadInterstitial() async {
    if (kIsWeb || _interstitialAd != null || _isLoadingInterstitial) return;
    _isLoadingInterstitial = true;
    try {
      final adUnitId = await _getInterstitialAdUnitId();
      await InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialAd = ad;
            _isLoadingInterstitial = false;
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                _interstitialAd = null;
                preloadInterstitial();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                _interstitialAd = null;
                _isLoadingInterstitial = false;
                preloadInterstitial();
              },
            );
          },
          onAdFailedToLoad: (error) {
            _isLoadingInterstitial = false;
          },
        ),
      );
    } catch (_) {
      _isLoadingInterstitial = false;
    }
  }

  /// Exibe o intersticial se estiver carregado. Caso contrário, carrega e exibe (pode haver delay).
  Future<void> loadAndShowInterstitial() async {
    if (kIsWeb) return;
    if (_interstitialAd != null) {
      _interstitialAd!.show();
      _interstitialAd = null;
      unawaited(preloadInterstitial());
      return;
    }
    _isLoadingInterstitial = true;
    try {
      final adUnitId = await _getInterstitialAdUnitId();
      await InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _isLoadingInterstitial = false;
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                preloadInterstitial();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                preloadInterstitial();
              },
            );
            ad.show();
          },
          onAdFailedToLoad: (_) {
            _isLoadingInterstitial = false;
          },
        ),
      );
    } catch (_) {
      _isLoadingInterstitial = false;
    }
  }
}
