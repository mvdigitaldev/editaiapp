import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../../features/profile/data/datasources/app_settings_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _appSettingsDataSourceProvider = Provider<AppSettingsDataSource>((ref) {
  return AppSettingsDataSourceImpl(Supabase.instance.client);
});

final adServiceProvider = Provider<AdService>((ref) {
  return AdService(ref.watch(_appSettingsDataSourceProvider));
});

class AdBannerWidget extends ConsumerStatefulWidget {
  const AdBannerWidget({super.key});

  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    final adService = ref.read(adServiceProvider);
    final adUnitId = await adService.getBannerAdUnitId();
    if (adUnitId == null || !mounted) return;

    final ad = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
              _bannerAd = loadedAd as BannerAd;
            });
          }
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (mounted) {
            setState(() => _hasError = true);
          }
        },
      ),
    );
    ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || _hasError) return const SizedBox.shrink();
    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox(
        height: 50,
        child: Center(child: SizedBox.shrink()),
      );
    }
    return SizedBox(
      height: 50,
      width: _bannerAd!.size.width.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
