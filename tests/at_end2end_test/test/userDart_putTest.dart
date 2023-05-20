import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:test/test.dart';

void main() async {
  test('Dart Java interoperabality: Putting key value pair', () async {
    final String path = getUriDirectoryPath();

    const String atSign = '@59albatross';

    // Configure the AtOnboardingPreference with file paths and storage options
    AtOnboardingPreference pref = AtOnboardingPreference()
      ..atKeysFilePath = "$path/.atsign/keys/${atSign}_key.atKeys"
      ..downloadPath = "$path/.atsign/temp/download"
      ..hiveStoragePath = "$path/.atsign/temp/hive"
      ..commitLogPath = "$path/.atsign/temp/commitlog"
      ..isLocalStoreRequired = true;

    // Create an instance of AtOnboardingServiceImpl with the atSign and preference
    AtOnboardingServiceImpl onboardingService =
        AtOnboardingServiceImpl(atSign, pref);

    // Authenticate the atSign and establish a connection
    await onboardingService.authenticate();

    // Get the AtClient instance from the onboarding service
    AtClient? atClient = onboardingService.atClient;

    //check if atClient is present or not
    if (atClient == null) {
      print('atClient is null');
      return;
    }

    // Create an AtKey object representing the key to be stored
    AtKey atKey = AtKey()
      ..key = 'rabbit'
      ..sharedBy = atSign
      ..namespace = 'lemon';

    // Put the value "likes carrots" associated with the AtKey on the server using the AtClient
    bool success = await atClient.put(atKey, "likes carrots");
    print('Write success? : $success');
    // Delay for 20 seconds
    await Future.delayed(Duration(seconds: 20));
    // Assert that the write operation was successful
    expect(success, true);
    // Exit the script
    exit(0);
  });
}

// returns ~/ directory path based on OS
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
