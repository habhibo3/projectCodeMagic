import 'dart:ui';

class DeviceCountry {
  final String name;
  final String flag;

  const DeviceCountry({required this.name, required this.flag});
}

/// Maps device locale to a default country for new anonymous profiles.
class LocaleCountry {
  static const _byCode = {
    'US': DeviceCountry(name: 'United States', flag: '🇺🇸'),
    'GB': DeviceCountry(name: 'United Kingdom', flag: '🇬🇧'),
    'UK': DeviceCountry(name: 'United Kingdom', flag: '🇬🇧'),
    'TN': DeviceCountry(name: 'Tunisia', flag: '🇹🇳'),
    'FR': DeviceCountry(name: 'France', flag: '🇫🇷'),
    'VN': DeviceCountry(name: 'Vietnam', flag: '🇻🇳'),
    'CN': DeviceCountry(name: 'China', flag: '🇨🇳'),
    'JP': DeviceCountry(name: 'Japan', flag: '🇯🇵'),
    'DE': DeviceCountry(name: 'Germany', flag: '🇩🇪'),
    'IT': DeviceCountry(name: 'Italy', flag: '🇮🇹'),
    'ES': DeviceCountry(name: 'Spain', flag: '🇪🇸'),
    'CA': DeviceCountry(name: 'Canada', flag: '🇨🇦'),
    'AU': DeviceCountry(name: 'Australia', flag: '🇦🇺'),
    'MA': DeviceCountry(name: 'Morocco', flag: '🇲🇦'),
    'DZ': DeviceCountry(name: 'Algeria', flag: '🇩🇿'),
    'EG': DeviceCountry(name: 'Egypt', flag: '🇪🇬'),
    'SA': DeviceCountry(name: 'Saudi Arabia', flag: '🇸🇦'),
    'AE': DeviceCountry(name: 'UAE', flag: '🇦🇪'),
    'IN': DeviceCountry(name: 'India', flag: '🇮🇳'),
    'BR': DeviceCountry(name: 'Brazil', flag: '🇧🇷'),
    'MX': DeviceCountry(name: 'Mexico', flag: '🇲🇽'),
    'KR': DeviceCountry(name: 'South Korea', flag: '🇰🇷'),
    'NG': DeviceCountry(name: 'Nigeria', flag: '🇳🇬'),
    'ZA': DeviceCountry(name: 'South Africa', flag: '🇿🇦'),
  };

  static const pickableCountries = [
    DeviceCountry(name: 'Tunisia', flag: '🇹🇳'),
    DeviceCountry(name: 'United States', flag: '🇺🇸'),
    DeviceCountry(name: 'United Kingdom', flag: '🇬🇧'),
    DeviceCountry(name: 'France', flag: '🇫🇷'),
    DeviceCountry(name: 'Vietnam', flag: '🇻🇳'),
    DeviceCountry(name: 'Japan', flag: '🇯🇵'),
    DeviceCountry(name: 'Morocco', flag: '🇲🇦'),
    DeviceCountry(name: 'Other', flag: '🌍'),
  ];

  static DeviceCountry fromDeviceLocale() {
    final code = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
    if (code != null && _byCode.containsKey(code)) {
      return _byCode[code]!;
    }
    return const DeviceCountry(name: 'Tunisia', flag: '🇹🇳');
  }
}
