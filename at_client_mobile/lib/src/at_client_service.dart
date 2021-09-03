import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/at_client_auth.dart';
import 'package:at_client_mobile/src/auth_constants.dart';
import 'package:at_client_mobile/src/onboarding_status.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class AtClientService {
  final AtSignLogger _logger = AtSignLogger('AtClientService');
  AtClient? _atClient;
  late AtClientManager atClientManager;
  AtClientAuthenticator? _atClientAuthenticator;
  late AtLookupImpl atLookUp;
  OnboardingStatus? _status;

  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();

  // Will create at client instance for a given atSign and perform cram+pkam auth to the server.
  // if pkam is successful, encryption keys will be set for the user./// Will create at client instance for a given atSign.
  Future<bool> _init(String atSign, AtClientPreference preference) async {
    _atClientAuthenticator ??= AtClientAuthenticator();
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, preference.namespace, preference);
    _atClient = AtClientManager.getInstance().atClient;
    atLookUp = _atClient!.getRemoteSecondary()!.atLookUp;
    if (preference.outboundConnectionTimeout > 0) {
      _atClient!.getRemoteSecondary()!.atLookUp.outboundConnectionTimeout =
          preference.outboundConnectionTimeout;
    }
    _atClientAuthenticator!.atLookUp =
        _atClient!.getRemoteSecondary()!.atLookUp;
    if (preference.privateKey != null) {
      _atClientAuthenticator!.atLookUp.privateKey = preference.privateKey;
      _atClient!.getRemoteSecondary()!.atLookUp.privateKey =
          preference.privateKey;
    }
    return true;
  }

  Future<bool> cramAuth(String cramSecret) async {
    return await _atClientAuthenticator!.cramAuth(cramSecret);
  }

  Future<bool> pkamAuth(String privateKey) async {
    return await _atClientAuthenticator!.pkamAuth(privateKey);
  }

  ///Returns `true` on persisting keys into keystore.
  Future<bool> persistKeys(String atSign) async {
    var pkamPrivateKey = await (KeychainUtil.getPkamPrivateKey(atSign)) ?? '';

    var pkamPublicKey = await (KeychainUtil.getPkamPublicKey(atSign)) ?? '';

    var encryptPrivateKey =
        await (KeychainUtil.getEncryptionPrivateKey(atSign)) ?? '';

    var encryptPublicKey = await KeychainUtil.getEncryptionPublicKey(atSign);

    var selfEncryptionKey =
        await (KeychainUtil.getSelfEncryptionKey(atSign)) ?? '';
    await _atClient!
        .getLocalSecondary()!
        .putValue(AT_PKAM_PUBLIC_KEY, pkamPublicKey);
    await _atClient!
        .getLocalSecondary()!
        .putValue(AT_PKAM_PRIVATE_KEY, pkamPrivateKey);
    await _atClient!
        .getLocalSecondary()!
        .putValue(AT_ENCRYPTION_PRIVATE_KEY, encryptPrivateKey);
    var updateBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey'
      ..isPublic = true
      ..sharedBy = atSign
      ..value = encryptPublicKey;
    await _atClient!
        .getLocalSecondary()!
        .executeVerb(updateBuilder, sync: true);

    await _atClient!
        .getLocalSecondary()!
        .putValue(AT_ENCRYPTION_SELF_KEY, selfEncryptionKey);
    var result = await _getKeysFromLocalSecondary(atSign);

    return result;
  }

  ///Throws [Error] of type [OnboardingStatus]
  ///if the details for [atsign] is not found in localsecondary.
  ///Returns `true` on successful fetching of all the details.
  Future<bool> _getKeysFromLocalSecondary(String atsign) async {
    var pkamPublicKey = await _atClient!.getLocalSecondary()!.getPublicKey();
    if (pkamPublicKey == null) {
      throw (OnboardingStatus.PKAM_PUBLIC_KEY_NOT_FOUND);
    }
    var pkamPrivateKey = await _atClient!.getLocalSecondary()!.getPrivateKey();
    if (pkamPrivateKey == null) {
      throw (OnboardingStatus.PKAM_PRIVATE_KEY_NOT_FOUND);
    }
    var encryptPrivateKey =
        await _atClient!.getLocalSecondary()!.getEncryptionPrivateKey();
    if (encryptPrivateKey == null) {
      throw (OnboardingStatus.ENCRYPTION_PRIVATE_KEY_NOT_FOUND);
    }
    var encryptPublicKey =
        await _atClient!.getLocalSecondary()!.getEncryptionPublicKey(atsign);
    if (encryptPublicKey == null) {
      throw (OnboardingStatus.ENCRYPTION_PUBLIC_KEY_NOT_FOUND);
    }

    var encryptSelfKey =
        await _atClient!.getLocalSecondary()!.getEncryptionSelfKey();
    if (encryptSelfKey == null) {
      throw (OnboardingStatus.SELF_ENCRYPTION_KEY_NOT_FOUND);
    }
    return false;
  }

  ///Returns `true` on successfully authenticating [atsign] with [cramSecret]/[privateKey].
  /// if pkam is successful, encryption keys will be set for the user.
  Future<bool> authenticate(
      String? atsign, AtClientPreference atClientPreference,
      {OnboardingStatus? status, String? jsonData, String? decryptKey}) async {
    if (atClientPreference.cramSecret == null) {
      atsign = _formatAtSign(atsign);
      if (atsign == null) {
        return false;
      }
      await _decodeAndStoreToKeychain(atsign, jsonData!, decryptKey!);
      atClientPreference.privateKey =
          await KeychainUtil.getPkamPrivateKey(atsign);
    }
    var result = await _init(atsign!, atClientPreference);
    if (!result) {
      return result;
    }
    if (_status != OnboardingStatus.ACTIVATE &&
        status != OnboardingStatus.ACTIVATE) {
      await _sync(atClientPreference, atsign);
    }
    result = await _atClientAuthenticator!.performInitialAuth(
      atsign,
      cramSecret: atClientPreference.cramSecret,
      pkamPrivateKey: atClientPreference.privateKey,
    );
    if (result) {
      var privateKey = atClientPreference.privateKey ??=
          await _keyChainManager.getPkamPrivateKey(atsign);
      _atClientAuthenticator!.atLookUp.privateKey = privateKey;
      _atClient!.getRemoteSecondary()!.atLookUp.privateKey = privateKey;
      await _sync(atClientPreference, atsign);
      await persistKeys(atsign);
    }
    return result;
  }

  ///Decodes the [jsonData] with [decryptKey] for [atsign] and stores it in keychain.
  Future<void> _decodeAndStoreToKeychain(
      String atsign, String jsonData, String decryptKey) async {
    var extractedjsonData = jsonDecode(jsonData);

    var pkamPublicKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE],
        decryptKey);

    var pkamPrivateKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE],
        decryptKey);
    await _keyChainManager.storePkamKeysToKeychain(atsign,
        privateKey: pkamPrivateKey, publicKey: pkamPublicKey);

    var encryptionPublicKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE],
        decryptKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_ENCRYPTION_PUBLIC_KEY, encryptionPublicKey);

    var encryptionPrivateKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE],
        decryptKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_ENCRYPTION_PRIVATE_KEY, encryptionPrivateKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_SELF_ENCRYPTION_KEY, decryptKey);
  }

  ///Returns `true` on successfully completing onboarding.
  /// Throws [OnboardingStatus.ATSIGN_NOT_FOUND] exception if atsign not found.
  /// Throws [OnboardingStatus.PRIVATE_KEY_NOT_FOUND] exception if privatekey not found.
  Future<bool> onboard(
      {required AtClientPreference atClientPreference, String? atsign}) async {
    _atClientAuthenticator = AtClientAuthenticator();
    if (atsign == null || atsign == '') {
      atsign = await _keyChainManager.getAtSign();
    } else {
      atsign = _formatAtSign(atsign);
    }
    if (atsign == null || atsign == '') {
      _logger.severe('Atsign not found');
      throw OnboardingStatus.ATSIGN_NOT_FOUND;
    }
    var privateKey = atClientPreference.privateKey;
    if (privateKey == null || privateKey == '') {
      privateKey = await _keyChainManager.getPkamPrivateKey(atsign);
    }
    if (privateKey == null || privateKey == '') {
      _logger.severe('PrivateKey not found');
      throw OnboardingStatus.PRIVATE_KEY_NOT_FOUND;
    }
    atClientPreference.privateKey = privateKey;
    await _init(atsign, atClientPreference);
    var keyRestorePolicyStatus = await getKeyRestorePolicy(atsign);
    if (keyRestorePolicyStatus == OnboardingStatus.ACTIVATE ||
        keyRestorePolicyStatus == OnboardingStatus.RESTORE) {
      _status = keyRestorePolicyStatus;
      throw (keyRestorePolicyStatus);
    }
    //no need of having pkam auth as unauth error can be thrown by keypolicy.
    var result = await pkamAuth(privateKey);
    if (result) await _sync(atClientPreference, atsign);
    return result;
  }

  ///Returns [OnboardingStatus] of the atsign by checking it with remote server.
  Future<OnboardingStatus> getKeyRestorePolicy(String atSign) async {
    var serverEncryptionPublicKey = await _getServerEncryptionPublicKey(atSign);
    var localEncryptionPublicKey =
        await _keyChainManager.getValue(atSign, KEYCHAIN_ENCRYPTION_PUBLIC_KEY);
    if (_isNullOrEmpty(localEncryptionPublicKey) &&
            _isNullOrEmpty(serverEncryptionPublicKey) ||
        (_isNullOrEmpty(serverEncryptionPublicKey) &&
            !(_isNullOrEmpty(localEncryptionPublicKey)))) {
      return OnboardingStatus.ACTIVATE;
    } else if (!_isNullOrEmpty(serverEncryptionPublicKey) &&
        _isNullOrEmpty(localEncryptionPublicKey)) {
      return OnboardingStatus.RESTORE;
    } else if (_isNullOrEmpty(serverEncryptionPublicKey) &&
        !_isNullOrEmpty(localEncryptionPublicKey)) {
      return OnboardingStatus.SYNC_TO_SERVER;
    } else {
      //both keys not null
      if (serverEncryptionPublicKey == localEncryptionPublicKey) {
        return OnboardingStatus.REUSE;
      } else {
        return OnboardingStatus.RESTORE;
      }
    }
  }

  Future<void> _sync(AtClientPreference preference, String? atSign) async {
    if ((preference.privateKey != null || preference.cramSecret != null) &&
        preference.syncStrategy != null) {
      AtClientManager.getInstance().syncService.sync();
    }
  }

  ///returns public key for [atsign] if found else returns null.
  Future<String?> _getServerEncryptionPublicKey(String atsign) async {
    var command = 'lookup:publickey$atsign\n';
    var result = await atLookUp.executeCommand(command);
    if (_isNullOrEmpty(result) || _isError(result)) {
      //checking for an authenticated connection
      command = 'llookup:public:publickey$atsign\n';
      result = await atLookUp.executeCommand(command);
      if (_isNullOrEmpty(result) || _isError(result)) {
        return null;
      }
    }
    return result!.replaceFirst('data:', '');
  }

  bool _isNullOrEmpty(String? key) {
    if (key == null) {
      return true;
    }
    key = key.replaceFirst('data:', '');
    if (key == 'null' || key.isEmpty) {
      return true;
    }
    return false;
  }

  bool _isError(String? key) {
    return key != null ? key.contains('error') : false;
  }

  ///Returns null if [atsign] is null else the formatted [atsign].
  ///[atsign] must be non-null.
  String? _formatAtSign(String? atsign) {
    if (atsign == null || atsign == '') {
      return null;
    }
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    atsign = !atsign.startsWith('@') ? '@' + atsign : atsign;
    return atsign;
  }
}

class BackupKeyConstants {
  static const String PKAM_PUBLIC_KEY_FROM_KEY_FILE = 'aesPkamPublicKey';
  static const String PKAM_PRIVATE_KEY_FROM_KEY_FILE = 'aesPkamPrivateKey';
  static const String ENCRYPTION_PUBLIC_KEY_FROM_FILE = 'aesEncryptPublicKey';
  static const String ENCRYPTION_PRIVATE_KEY_FROM_FILE = 'aesEncryptPrivateKey';
  static const String SELF_ENCRYPTION_KEY_FROM_FILE = 'selfEncryptionKey';
}

class KeychainUtil {
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();

  static Future<String?> getPkamPrivateKey(String atSign) async {
    var pkamPrivateKey = await _keyChainManager.getPkamPrivateKey(atSign);
    return pkamPrivateKey;
  }

  static Future<String?> getPkamPublicKey(String atSign) async {
    return await _keyChainManager.getPkamPublicKey(atSign);
  }

  static Future<String?> getPrivateKey(String atSign) async {
    return await getPkamPrivateKey(atSign);
  }

  static Future<String?> getPublicKey(String atSign) async {
    return await getPkamPublicKey(atSign);
  }

  static Future<String?> getEncryptionPrivateKey(String atSign) async {
    return await _keyChainManager.getEncryptionPrivateKey(atSign);
  }

  static Future<String?> getEncryptionPublicKey(String atSign) async {
    return await _keyChainManager.getEncryptionPublicKey(atSign);
  }

  static Future<String?> getAESKey(String atsign) async {
    return await _keyChainManager.getValue(
        atsign, KEYCHAIN_SELF_ENCRYPTION_KEY);
  }

  static Future<String?> getSelfEncryptionKey(String atSign) async {
    return await _keyChainManager.getSelfEncryptionAESKey(atSign);
  }

  static Future<String?> getAtSign() async {
    return await _keyChainManager.getAtSign();
  }

  static Future<List<String>?> getAtsignList() async {
    return await _keyChainManager.getAtSignListFromKeychain();
  }

  static Future<void> resetAtSignFromKeychain(String atsign) async {
    return await _keyChainManager.resetAtSignFromKeychain(atsign);
  }

  static Future<void> deleteAtSignFromKeychain(String atsign) async {
    return await _keyChainManager.deleteAtSignFromKeychain(atsign);
  }

  static Future<bool> makeAtSignPrimary(String atsign) async {
    var atSignWithStatus = await getAtsignsWithStatus();
    if (atSignWithStatus[atsign]!) {
      return false;
    }
    return await _keyChainManager.makeAtSignPrimary(atsign);
  }

  static Future<Map<String, bool?>> getAtsignsWithStatus() async {
    return await _keyChainManager.getAtsignsWithStatus();
  }

  static Future<Map<String, String>> getEncryptedKeys(String atsign) async {
    var aesEncryptedKeys = {};
    // encrypt pkamPublicKey with AES key
    var pkamPublicKey = await getPkamPublicKey(atsign);
    var aesEncryptionKey = await getAESKey(atsign);
    var encryptedPkamPublicKey =
        EncryptionUtil.encryptValue(pkamPublicKey!, aesEncryptionKey!);
    aesEncryptedKeys[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE] =
        encryptedPkamPublicKey;

    // encrypt pkamPrivateKey with AES key
    var pkamPrivateKey = await getPkamPrivateKey(atsign);
    var encryptedPkamPrivateKey =
        EncryptionUtil.encryptValue(pkamPrivateKey!, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE] =
        encryptedPkamPrivateKey;

    // encrypt encryption public key with AES key
    var encryptionPublicKey = await getEncryptionPublicKey(atsign);
    var encryptedEncryptionPublicKey =
        EncryptionUtil.encryptValue(encryptionPublicKey!, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE] =
        encryptedEncryptionPublicKey;

    // encrypt encryption private key with AES key
    var encryptionPrivateKey = await getEncryptionPrivateKey(atsign);
    var encryptedEncryptionPrivateKey =
        EncryptionUtil.encryptValue(encryptionPrivateKey!, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE] =
        encryptedEncryptionPrivateKey;

    // store  self encryption key as it is.This will be same as AES key in key zip file
    var selfEncryptionKey = await getSelfEncryptionKey(atsign);
    aesEncryptedKeys[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE] =
        selfEncryptionKey;
    return Map<String, String>.from(aesEncryptedKeys);
  }
}
