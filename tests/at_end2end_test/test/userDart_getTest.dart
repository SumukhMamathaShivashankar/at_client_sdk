import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:test/test.dart';

void main() async {
  test('Dart Java interoperabality: Putting key value pair', () async {
    // Retrieve the path of the directory where the script is running
    final String path = getUriDirectoryPath();
    const String dart = '@59albatross';
    const String java = '@experimental7';
    const String namespace = 'lemon';

    // Configure the AtOnboardingPreference with file paths and storage options
    AtOnboardingPreference pref = AtOnboardingPreference()
      ..atKeysFilePath = "$path/.atsign/keys/${dart}_key.atKeys"
      ..downloadPath = "$path/.atsign/temp/download"
      ..hiveStoragePath = "$path/.atsign/temp/hive"
      ..commitLogPath = "$path/.atsign/temp/commitlog"
      ..isLocalStoreRequired = true;

    // Create an instance of AtOnboardingServiceImpl with the dart @sign and preference
    AtOnboardingService onboardingService = AtOnboardingServiceImpl(dart, pref);

    // Authenticate the dart @sign and establish a connection
    final bool authenticated = await onboardingService.authenticate();

    // Create an AtKey object representing the shared key to be retrieved
    AtKey atKey = AtKey()
      ..key = 'Dog'
      ..namespace = namespace
      ..sharedBy = java
      ..sharedWith = dart;

    // Get the AtClient instance from the onboarding service
    AtClient atClient = onboardingService.atClient!;

    // Get the value associated with the shared key from the server using the AtClient
    String success = (await atClient.get(atKey)).value;
    print(success);

    // Assert that the retrieved value is equal to "likes bones"
    expect(success, "likes bones");
  });
}

// Helper function to determine the home directory path based on the operating system
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
