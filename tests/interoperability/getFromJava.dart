import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

void main() async {
  final String path = getUriDirectoryPath();
  const String dart = '@59albatross';
  const String java = '@experimental7';
  const String namespace = 'lemon';
  AtOnboardingPreference pref = AtOnboardingPreference()
    ..atKeysFilePath = "$path/.atsign/keys/${dart}_key.atKeys"
    ..downloadPath = "$path/.atsign/temp/download"
    ..hiveStoragePath = "$path/.atsign/temp/hive"
    ..commitLogPath = "$path/.atsign/temp/commitlog"
    ..isLocalStoreRequired = true;
  AtOnboardingService onboardingService = AtOnboardingServiceImpl(dart, pref);
  final bool authenticated = await onboardingService.authenticate();
  AtKey atKey = AtKey()
    ..key = 'Dog'
    ..namespace = namespace
    ..sharedBy = java
    ..sharedWith = dart;
  AtClient atClient = onboardingService.atClient!;
  print((await atClient.get(atKey)).value);
}

/// returns ~/ directory path based on OS
String getUriDirectoryPath() {
  String home = "";
  if (Platform.isMacOS) {
    home = Platform.environment['HOME']!;
  } else if (Platform.isLinux) {
    home = Platform.environment['HOME']!;
  } else if (Platform.isWindows) {
    home = Platform.environment['UserProfile']!;
  }
  return home;
}
