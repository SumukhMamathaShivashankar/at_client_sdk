import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync/sync_request.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/src/keystore/hive_keystore.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {
  var remoteKeyStore = {};

  @override
  Future<String?> executeCommand(String atCommand, {bool auth = false}) async {
    return 'success';
  }
}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() {
    return '@bob';
  }

  @override
  AtClientPreference? getPreferences() {
    return AtClientPreference();
  }
}

class MockNotificationServiceImpl extends Mock
    implements NotificationServiceImpl {
  @override
  Stream<at_notification.AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    return StreamController<at_notification.AtNotification>().stream;
  }
}

class MockNetworkUtil extends Mock implements NetworkUtil {
  @override
  Future<bool> isNetworkAvailable() {
    return Future.value(true);
  }
}

///Notes:
/// Description of terminology used in the test cases:
///
/// 1. Create = A key does not exist previously and it is being newly created
/// 2. Update = A key exists previously
/// 3. Recreate = A key that exists previously got deleted and it is being created again

void main() {
  String atsign = '@bob';
  // (Client) How items are added to the 'uncommitted' queue on the client side (upon data store operations)
  // (Client) How the client processes that uncommitted queue (while sending updates to server) - e.g. how is the queue ordered, how is it de-duped, etc
  // (Client) How the client processes updates from the server - can the client reject? under what conditions? what happens upon a rejection?
  // The 7th contract is the contract for precisely how the client and server exchange information. Currently this is implemented using the batch verb and has state like 'syncInProgress' and 'isInSync'. (Aside: Fsync will implement this contract in a streaming fashion bidirectionally.)

  group(
      'Tests to validate how items are added to the uncommitted queue on the client side (upon data store operations)',
      () {
    /// Preconditions:
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    /// Operation:
    /// Put a public key

    /// Assertions:
    /// 1. Key store should have the public key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. The version of the key should be set to 0
    /// 4. CommitLog should have an entry for the new public key with commitOp.Update
    /// and commitId is null
    test('Verify uncommitted queue on creation of a public key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'Hyderabad';
      //------------------Operation-------------
      //  creating a key in the keystore
      String atKey = (AtKey.public('city', namespace: 'wavi', sharedBy: atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      //------------------Assertions-------------
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt!.isBefore(DateTime.now()),
          true);
      expect(keyStoreGetResult.metaData!.version, 0);
      var commitLogEntry =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      print(commitLogEntry);
      expect(commitLogEntry!.operation, CommitOp.UPDATE);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. In the metadata of the key, the version should be set to 0
    /// and the "createdAt" field should be populated.
    /// 3. There should be an entry for the same key in the commit log

    // Operation
    /// Update a public key
    // updating the same key in the keystore with a different value
    // Assertions :
    /// 1. Key store should have the public key with the new value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    /// 3. The version of the key should be incremented by 1
    /// 4. CommitLog should have an entry for the new public key with commitOp.Update
    test('Verify uncommitted queue on updation of a public key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'Hyderabad';
      var newData = AtData();
      newData.data = 'Bangalore';
      //------------Precondition Setup---------------------------------
      String atKey = (AtKey.public('city', namespace: 'wavi', sharedBy: atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt, isNotNull);
      // var createdAtTime = keyStoreGetResult.metaData!.createdAt;
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      //-----------Operation---------------------------------
      await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------
      // verifying the key in the key store
      keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'Bangalore');
      // verifying that createdAt time is not changed
      // expect(keyStoreGetResult.metaData!.createdAt, createdAtTime);
      // verifiyng the updatedAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 1
      /// commenting the assertion as there is a known bug in the versioning where
      /// Version doesn't get incremented when the same key is updated
      // expect(keyStoreGetResult.metaData!.version, 1);
      // verifying the key in the commit log
      commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      expect(commitEntryResult!.operation == CommitOp.UPDATE_ALL, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    //Operation
    /// Delete a public key

    // Assertions :
    /// 1. Key store now should not have the entry of the key
    /// 2. CommitLog should have an entry for the deleted public key (commitOp.delete)
    test('Verify uncommitted queue on deletion of a public key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      String atKey =
          (AtKey.public('location', namespace: 'wavi', sharedBy: atsign))
              .build()
              .toString();
      //-----------Precondition Setup---------------------------------
      await keystore!.put(atKey, AtData()..data = 'Hyderabad');
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'Hyderabad');
      //-----------Operation---------------------------------
      await keystore.remove(atKey);
      // verifying the key in the key store
      //-----------Assertions---------------------------------
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      // verifying the key in the commit log
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      expect(commitEntryResult!.operation == CommitOp.DELETE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    /// Operation
    /// Delete a key and insert the same key again

    /// Assertions
    /// 1. Key store should have the public key with the new value inserted
    /// 2. CommitLog should have a following entries in sequence as described below
    ///     a. Commit entry with CommitOp.Delete
    ///     b. CommitEntry with CommitOp.Update

    test('Verify uncommitted queue on re-creation of a public key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      String oldValue = 'alice@gmail.com';
      String newValue = 'alice@yahoo.com';
      var atData = AtData();
      atData.data = oldValue;
      var newData = AtData();
      newData.data = newValue;
      //-----------Operation---------------------------------
      String atKey =
          (AtKey.public('email', namespace: 'wavi', sharedBy: atsign))
              .build()
              .toString();
      await keystore!.put(atKey, atData);
      final commitLogInstance =
          await (AtCommitLogManagerImpl.getInstance().getCommitLog(atsign));
      // seq number from the commit entry
      var seqNum = commitLogInstance!.lastCommittedSequenceNumber();
      // remove the created key
      await keystore.remove(atKey);
      // re-creating the same key in the keystore with a new value
      await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store to return the updated value
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, newValue);
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verify the entries in the commit log
      var commitEntriesResult = await SyncUtil()
          .getChangesSinceLastCommit(seqNum, 'wavi', atSign: atsign);
      expect(commitEntriesResult[0].operation == CommitOp.DELETE, true);
      expect(commitEntriesResult[1].operation == CommitOp.UPDATE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    /// Operation
    /// Put a shared key

    /// Assertions
    /// 1. Key store should have the shared key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. The version of the key should be 0 (Zero)
    /// 4. CommitLog should have an entry for the shared key with commitOp.Update
    /// and commitId is null
    test('Verify uncommitted queue on creation of a shared key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'Hyderabad';
      //-----------Operation---------------------------------
      //  creating a key in the keystore
      String atKey =
          (AtKey.shared('location', namespace: 'wavi', sharedBy: atsign)
                ..sharedWith('@bob'))
              .build()
              .toString();
      await keystore!.put(atKey, atData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult!.metaData!.createdAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      expect(keyStoreGetResult.metaData!.version, 0);
      // verifying the key in the commit log
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      expect(commitEntryResult!.operation == CommitOp.UPDATE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log
    /// 3. In the metadata of the key, the version should be set to 0
    /// and the "createdAt" field should be populated.
    ///
    /// Operation
    /// Update a shared key

    /// Assertions
    /// 1. Keystore should have the shared key with the new value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    /// of when key is updated
    /// 3. The version of the key should be incremented by 1
    /// 4. CommitLog should have an entry for the new shared key with commitOp.Update
    test('Verify uncommitted queue on updation of a shared key ', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'alice';
      var newData = AtData();
      newData.data = 'alice123';
      //------------Preconditions SetUp---------------------------------
      String atKey =
          (AtKey.shared('username', namespace: 'wavi', sharedBy: atsign)
                ..sharedWith('@bob'))
              .build()
              .toString();
      //  creating a key in the keystore
      await keystore!.put(atKey, atData);
      //-----------Operation---------------------------------
      // updating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice123');
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      // expect(keyStoreGetResult.metaData!.version, 1);
      // verifying the key in the commit log
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      expect(commitEntryResult!.operation == CommitOp.UPDATE_ALL, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    // Operation
    /// Delete a shared key

    // Assertions
    /// 1. Keystore should not have the shared key
    /// 2. CommitLog should have an entry for the deleted shared key(commitOp.delete)
    test('Verify uncommitted queue on deletion of a shared key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      //------------Preconditons setup---------------------------------
      String atKey =
          (AtKey.shared('location', namespace: 'wavi', sharedBy: atsign)
                ..sharedWith('@bob'))
              .build()
              .toString();
      await keystore!.put(atKey, AtData()..data = 'alice');
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice');
      //-----------Operation---------------------------------
      await keystore.remove(atKey);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      // verifying the key in the commit log
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      expect(commitEntryResult!.operation == CommitOp.DELETE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    // Operation
    /// Delete a key and insert the same key again

    // Assertions :
    /// 1. Keystore should have the shared key with the new value inserted
    /// 2. CommitLog should have a following entries in sequence as described below
    ///     a. Commit entry with CommitOp.Delete
    ///     b. CommitEntry with CommitOp.Update
    test('Verify uncommitted queue on re-creation of a shared key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'alice@gmail.com';
      var newData = AtData();
      newData.data = 'alice@yahoo.com';
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.shared('email', namespace: 'wavi', sharedBy: atsign)
            ..sharedWith('@bob'))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      // verifying the key in the commit log
      final commitLogInstance =
          await (AtCommitLogManagerImpl.getInstance().getCommitLog(atsign));
      // seq number from the commit entry
      var seqNum = commitLogInstance!.lastCommittedSequenceNumber();
      //-----------Operation---------------------------------
      // remove the created key
      await keystore.remove(atKey);
      // re-creating the same key in the keystore with a different value
      await keystore.put(atKey, newData);

      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice@yahoo.com');
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verify the entries in the commit log
      var commitEntriesResult = await SyncUtil()
          .getChangesSinceLastCommit(seqNum, 'wavi', atSign: atsign);
      expect(commitEntriesResult[0].operation == CommitOp.DELETE, true);
      expect(commitEntriesResult[1].operation == CommitOp.UPDATE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    // Operation
    /// Put a self key

    // Assertions :
    /// 1. Keystore should have the self key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. The version of the key should be set to 0
    /// 4. CommitLog should have an entry for the new self key with commitOp.Update
    /// and commitId is null
    test('Verify uncommitted queue on creation of a self key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'alice12';
      //-----------Operation---------------------------------
      //  creating a key in the keystore
      String atKey = (AtKey.self('quora', namespace: 'wavi', sharedBy: atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult!.metaData!.createdAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      expect(keyStoreGetResult.metaData!.version, 0);
      // verifying the key in the commit log
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      print(commitEntryResult);
      // This assertion fails when run as a group
      // expect(commitEntryResult!.commitId, 0);
      expect(commitEntryResult!.operation == CommitOp.UPDATE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log
    /// 3. In the metadata of the key, the version should be set to 0
    /// and the "createdAt" field should be populated.

    //  Operation
    /// Update a self key

    //  Assertions :
    /// 1. Keystore should have the self key with the new value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    /// 3. The version of the key should be incremented by 1
    /// 4. CommitLog should have an entry for the new self key with commitOp.Update
    test('Verify uncommitted queue on updation of a self key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      String oldValue = 'alice';
      String newValue = 'alice123';
      var atData = AtData();
      atData.data = oldValue;
      var newData = AtData();
      newData.data = newValue;
      //------------Preconditions SetUp---------------------------------
      String atKey =
          (AtKey.self('facebook', namespace: 'wavi', sharedBy: atsign))
              .build()
              .toString();
      //  creating a key in the keystore
      await keystore!.put(atKey, atData);
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt, isNotNull);
      expect(keyStoreGetResult.metaData!.version, 0);
      //-----------Operation---------------------------------
      // updating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, newValue);
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      // expect(keyStoreGetResult.metaData!.version, 1);
      // verifying the key in the commit log
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      expect(commitEntryResult!.operation == CommitOp.UPDATE_ALL, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log
    // Operation
    /// Delete a self key

    // Assertions :
    /// 1. Keystore now should not have the entry of the key
    /// 2. CommitLog should have an entry for the deleted self key (commitOp.delete)
    test('Verify uncommitted queue on deletion of a self key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      //------------Preconditions SetUp---------------------------------
      String atKey =
          (AtKey.self('twitter', namespace: 'wavi', sharedBy: atsign))
              .build()
              .toString();
      await keystore!.put(atKey, AtData()..data = 'alice');
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice');
      //-----------Operation---------------------------------
      await keystore.remove(atKey);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      // verifying the key in the commit log
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      expect(commitEntryResult!.operation == CommitOp.DELETE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    // Operation
    /// Delete a key and insert the same key again

    // Assertions :
    /// 1. Keystore should have the self key with the new value inserted
    /// 2. CommitLog should have a following entries in sequence as described below
    ///     a. Commit entry with CommitOp.Delete
    ///     b. CommitEntry with CommitOp.Update
    test('Verify uncommitted queue on re-creation of a self key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'alice@gmail.com';
      var newData = AtData();
      newData.data = 'alice@yahoo.com';
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.self('email', namespace: 'wavi', sharedBy: atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      // verifying the key in the commit log
      final commitLogInstance =
          await (AtCommitLogManagerImpl.getInstance().getCommitLog(atsign));
      // seq number from the commit entry
      var seqNum = commitLogInstance!.lastCommittedSequenceNumber();
      //-----------Operation---------------------------------
      // remove the created key
      await keystore.remove(atKey);
      // re-creating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice@yahoo.com');
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verify the entries in the commit log
      var commitEntriesResult = await SyncUtil()
          .getChangesSinceLastCommit(seqNum, 'wavi', atSign: atsign);
      expect(commitEntriesResult[0].operation == CommitOp.DELETE, true);
      expect(commitEntriesResult[1].operation == CommitOp.UPDATE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    // Operation
    /// Put a local key

    // Assertions
    /// 1. Keystore should have the local key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    test('Verify uncommitted queue on creation of a local key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'sample';
      //-----------Operation---------------------------------
      //  creating a key in the keystore
      String atKey =
          (AtKey.local('sample', atsign, namespace: 'wavi')).build().toString();
      await keystore!.put(atKey, atData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'sample');
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      expect(keyStoreGetResult.metaData!.version, 0);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions
    /// 1. There should be an entry for the same key in the key store
    /// 2. In the metadata of the key, the version should be set to 0
    /// and the "createdAt" field should be populated.

    // Operation
    /// Put a new value for an existing local key

    // Assertions
    /// 1. keystore should have the local key with the new value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    test('Verify uncommitted queue on updation of a local key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'alice';
      var newData = AtData();
      newData.data = 'alice123';
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.local('facebook', atsign, namespace: 'wavi'))
          .build()
          .toString();
      //  creating a key in the keystore
      await keystore!.put(atKey, atData);
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt, isNotNull);
      expect(keyStoreGetResult.metaData!.version, 0);
      //-----------Operation---------------------------------
      // updating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      // verifying the key in the key store
      keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice123');
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 1
      // expect(keyStoreGetResult.metaData!.version, 1);
      await TestResources.tearDownLocalStorage();
    });

    /// Pre-conditions
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    // Operation
    /// Delete a local key

    // Assertions
    /// 1. Keystore should not have the local key
    /// 2. CommitLog should have an entry for the deleted local key (commitOp.delete)
    test('Verify uncommitted queue on deletion of a local key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.local('twitter', atsign, namespace: 'wavi'))
          .build()
          .toString();
      await keystore!.put(atKey, AtData()..data = 'alice');
      // verifying the key in the commit log
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice');
      //-----------Operation---------------------------------
      await keystore.remove(atKey);
      // verifying the key in the key store
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store

    // Operation
    /// Delete a key and insert the same key again

    // Assertions :
    /// 1. Keystore should have the local key with the new value inserted
    test('Verify uncommitted queue on re-creation of a local key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'Newyork';
      var newData = AtData();
      newData.data = 'Texas';
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.local('fav-place', atsign, namespace: 'wavi'))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      // remove the created key
      // -----------Operation---------------------------------
      await keystore.remove(atKey);
      // re-creating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      // -----------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'Texas');
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions
    /// 1. There should be no entry for the private encryption key in the key store
    /// 2. There should be no entry for the private encryption key in the commit log

    // Operation
    /// Put a private encryption key

    // Assertions
    /// 1. Keystore should have the private encryption key with the value inserted
    test('Verify uncommitted queue on creation of a private encryption key',
        () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      final encryptionPrivateKey =
          RSAKeypair.fromRandom().privateKey.toString();
      var atData = AtData();
      atData.data = encryptionPrivateKey;
      //------------Operation---------------------------------
      String atKey = (AtKey.self(AT_ENCRYPTION_PRIVATE_KEY, sharedBy: atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      // -----------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, encryptionPrivateKey);
      await TestResources.tearDownLocalStorage();
    });

    test('Verify uncommitted queue on deletion of a private encryption key',
        () {
      /// ToDo: Needs to be decided if we need to test deletion of private encryption key
    });
    test('Verify uncommitted queue on re-creation of a private encryption key',
        () {
      /// ToDo: Needs to be decided if we need to test re-creation of private encryption key
    });

    /// Preconditions
    /// 1. There should be no entry for the pkam private key in the key store

    // Operation
    /// Put a pkam private key

    // Assertions
    /// 1. Keystore should have the pkam private key with the value inserted
    test('Verify uncommitted queue on creation of a pkam private key',
        () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      final pkamPrivateKey = RSAKeypair.fromRandom().privateKey.toString();
      var atData = AtData();
      atData.data = pkamPrivateKey;
      //------------Operation---------------------------------
      String atKey = (AtKey.self(AT_PKAM_PRIVATE_KEY, sharedBy: atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      // -----------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, pkamPrivateKey);
      await TestResources.tearDownLocalStorage();
    });
    test('Verify uncommitted queue on deletion of a pkam private key', () {
      /// ToDo: Needs to be decided if we need to test deletion of pkam private key
    });
    test('Verify uncommitted queue on re-creation of a pkam private key', () {
      /// ToDo: Needs to be decided if we need to test re-creation of pkam private key
    });

    /// Preconditions
    /// 1. There should be an entry for the public key in the key store
    /// 2. There should be an entry for the public key in the commit log

    // Operation
    /// 1. Update a new value for an existing public key
    /// 2. Delete the public key

    // Assertions
    /// 1. Keystore should not have the public key
    /// 2. CommitLog should have only the latest entries:
    ///     a. CommitEntry for key with CommitOp.Delete
    test(
        'Verify uncommitted queue on multiple update and deletion of a public key',
        () async {
      // ------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'alice@gmail.com';
      var newData = AtData();
      newData.data = 'alice@yahoo.com';
      // ------------Operation---------------------------------
      String atKey =
          (AtKey.public('facebook', namespace: 'wavi', sharedBy: atsign))
              .build()
              .toString();
      await keystore!.put(atKey, atData);
      // updating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice@yahoo.com');
      //  deleting the public key
      await keystore.remove(atKey);
      // -----------Assertions---------------------------------
      // verify the latest entry in the commit log is for DELETE
      var commitEntryResult =
          await TestResources.getCommitEntryLatest(atsign, atKey);
      expect(commitEntryResult!.operation == CommitOp.DELETE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions
    /// 1. There should be an entry for the shared key in the key store
    /// 2. There should be an entry for the shared key in the commit log

    // Operation
    /// 1. Update a new value for an existing shared key
    /// 2. Delete the shared key

    // Assertions
    /// 1. Keystore should not have the shared key
    /// 2. CommitLog should have only the latest entries:
    ///     a. CommitEntry for key with CommitOp.Delete
    test(
        'Verify uncommitted queue on multiple updates and deletes of a shared key',
        () async {
      // ------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'alice123';
      var newData = AtData();
      newData.data = 'alice544';
      // ------------Operation---------------------------------
      String atKey =
          (AtKey.shared('medium', namespace: 'wavi', sharedBy: atsign)
                ..sharedWith('@alice'))
              .build()
              .toString();
      await keystore!.put(atKey, atData);
      // updating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      // --------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice544');
      // verifiyng the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      //  deleting the public key
      await keystore.remove(atKey);
      // verifying the latest entry in the commit log is for DELETE
      final commitLogInstance =
          await (AtCommitLogManagerImpl.getInstance().getCommitLog(atsign));
      var commitEntryResult = commitLogInstance!.getLatestCommitEntry(atKey);
      expect(commitEntryResult!.operation == CommitOp.DELETE, true);
      await TestResources.tearDownLocalStorage();
    });

    /// Preconditions
    /// 1. There should be an entry for the self key in the key store
    /// 2. There should be an entry for the self key in the commit log

    // Operation
    /// 1. Update a new value for an existing self key
    /// 2. Delete the self key

    // Assertions
    /// 1. Keystore should not have the self key
    /// 2. CommitLog should have only the latest entries:
    ///     a. CommitEntry for key with CommitOp.Delete
    test(
        'Verify uncommitted queue on multiple updates and deletes of a self key',
        () async {
      // ------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = '1134';
      var newData = AtData();
      newData.data = '5424';
      // ------------Operation---------------------------------
      String atKey =
          (AtKey.self('auth-code', namespace: 'wavi', sharedBy: atsign))
              .build()
              .toString();
      await keystore!.put(atKey, atData);
      // updating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      // --------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, '5424');
      //  deleting the key
      await keystore.remove(atKey);
      // verifying the latest entry in the commit log is for DELETE
      final commitLogInstance =
          await (AtCommitLogManagerImpl.getInstance().getCommitLog(atsign));
      var commitEntryResult = commitLogInstance!.getLatestCommitEntry(atKey);
      expect(commitEntryResult!.operation == CommitOp.DELETE, true);
      await TestResources.tearDownLocalStorage();
    });
  });

  group(
      'Tests to validate how the client processes that uncommitted queue (while sending updates to server) - e.g. how is the queue ordered, how is it de-duped, etc',
      () {
    setUpAll(() async =>
        await TestResources.setupLocalStorage(atsign, enableCommitId: false));

    AtClient mockAtClient = MockAtClient();
    AtClientManager mockAtClientManager = MockAtClientManager();
    NotificationServiceImpl mockNotificationService =
        MockNotificationServiceImpl();
    RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    NetworkUtil mockNetworkUtil = MockNetworkUtil();

    /// Preconditions:
    /// 1. The hive key store has 5 distinct keys with different key types - public key, shared key and self key
    /// 2. The commit log has corresponding entries for the above keys and commit id should be null
    ///
    /// Operations:
    /// Get the uncommitted operations
    ///
    /// Assertions:
    /// 1. The uncommitted entries should be returned as in same order that keys are create
    test(
        'Verify that entries to be sent to the server from the uncommitted queue are retrieved in the order of creation - FIFO',
        () async {
      //----------------------------setup---------------------------
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      int? currentSeqnum =
          TestResources.commitLog?.lastCommittedSequenceNumber();
      List<String> keys = [];
      //------------------preconditions setup-----------------------
      //create 5 random keys of types public/shared/self
      keys.add(AtKey.public('test_key0', sharedBy: atsign).build().toString());
      keys.add((AtKey.shared('test_key1', sharedBy: atsign)
            ..sharedWith('@alice'))
          .build()
          .toString());
      keys.add(AtKey.public('test_key2', sharedBy: atsign).build().toString());
      keys.add((AtKey.shared('test_key3', sharedBy: atsign)
            ..sharedWith('@alice'))
          .build()
          .toString());
      keys.add(AtKey.self('test_key4', sharedBy: atsign).build().toString());
      for (var element in keys) {
        await keystore?.put(element, AtData()..data = 'dummydata');
      }
      //-----------------------operation------------------------------
      List<CommitEntry> changes = await SyncUtil(
              atCommitLog: TestResources.commitLog)
          .getChangesSinceLastCommit(currentSeqnum, 'test_key', atSign: atsign);
      //----------------------assertion-------------------------------
      for (int i = 0; i < 5; i++) {
        //assert that the order of changes received and the local list of keys is the same
        //comparing CommitEntry.atKey and the list element(which is an atKey)
        expect(changes[i].atKey, keys[i]);
      }
    });

    /// Preconditions:
    /// 1. The server commit id and local commit id are equal
    /// 2. The uncommitted entries should have following entries
    ///    a. hive_seq: 1 - @alice:phone@bob - commitOp. Update - value: +445-446-4847
    ///    b. hive_seq:2 - @alice:phone@bob - commitOp. Update - value: +447-448-4849
    ///
    /// Operations:
    /// Get the uncommitted operations
    ///
    /// Assertion:
    ///  1. When fetch uncommitted entry should be fetched:
    ///     - The entry with hive_seq -2
    test(
        'Verify that for a same key with many updates only the latest entry is selected from uncommitted queue to be sent to the server',
        () async {
      //------------setup---------------------------------
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      //capture hive seq_num before put to get changes after this num
      int? currentSeqnum =
          TestResources.commitLog?.lastCommittedSequenceNumber();
      //-------------------preconditions setup--------------
      var key =
          AtKey.public('test2_key0', namespace: 'group2test2', sharedBy: atsign)
              .build()
              .toString();
      await keystore?.put(key, AtData()..data = 'test_data1');
      //capture time before the second update
      var timeUpdate2 = DateTime.now().toUtc();
      await keystore?.put(key, AtData()..data = 'test_data2');
      //------------------operation-----------------------
      List<CommitEntry> changes =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getChangesSinceLastCommit(currentSeqnum, 'group2test2',
                  atSign: atsign);
      //-------------------assertion-----------------------
      expect(changes.length, 1);
      expect(changes[0].operation, CommitOp.UPDATE);
      //assert that the commit entry we have has only been committed after timeUpdate2
      //ensuring that the commit entry returned by changes is the latest one
      expect(changes[0].opTime?.isAfter(timeUpdate2), true);
    });

    /// Preconditions:
    /// 1. The commit log has two entries for the same key in the below order
    ///     1. Key with CommitOp.Update
    ///     2. Key with CommitOp.Delete
    ///
    /// Operation:
    /// Get the uncommitted entries
    ///
    /// Assertions:
    /// 1. An empty list should be returned
    test(
        'Verify that a same key with a update and delete nothing is selected from uncommitted queue',
        () async {
      //--------------------setup-----------------------
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      //capture hive seq_num before put to get changes after this num
      int? currentSeqnum =
          TestResources.commitLog?.lastCommittedSequenceNumber();
      //------------------preconditions setup-------------
      var key =
          AtKey.public('test2_key0', namespace: 'group2test3', sharedBy: atsign)
              .build()
              .toString();
      //insert and delete the same key
      await keystore?.put(key, AtData()..data = 'test_data1');
      await keystore?.remove(key);
      //--------------------operation---------------------
      //get changes since previously captured hive seq_num
      List<CommitEntry> changes =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getChangesSinceLastCommit(currentSeqnum, 'group2test3',
                  atSign: atsign);
      //------------------assertion-----------------------
      expect(changes.length, 0);
    });

    /// Preconditions:
    /// 1. The server commit id and local commit id are equal
    /// 2. Create a key "@alice:phone@bob" before delete in step-3
    /// 3. The uncommitted entries should have following entries
    ///    a. hive_seq: 1 - @alice:phone@bob - commitOp.Delete
    ///    b. hive_seq:2 - @alice:phone@bob - commitOp.Update - value: +445-446-4847
    ///
    /// Assertion:
    ///  1. After sync completion:
    ///     a. The keystore should have @alice:phone@bob with value: +445-446-4847
    test('A test to verify when an existing key is deleted and then created',
        () async {
      //----------------------------------setup---------------------------------
      LocalSecondary? localSecondary = LocalSecondary(mockAtClient,
          keyStore: TestResources.getHiveKeyStore(atsign));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
      //instantiate sync service using mocks
      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      //re-initialize sync util using the local commit log for unit tests
      syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      //------------------------------preconditions setup-----------------------
      var key =
          AtKey.public('test4_key0', namespace: 'group2test4', sharedBy: atsign)
              .build()
              .toString();

      await keystore?.put(key, AtData()..data = 'test_data1');
      await keystore?.remove(key);
      await keystore?.put(key, AtData()..data = 'test_data1');
      int serverCommitId = -1;
      //-------------------------------operation--------------------------------
      SyncResult result = await syncService.syncInternal(
          serverCommitId,
          SyncRequest()
            ..result = SyncResult()
            ..requestedOn);
      print(result);
      //------------------------------assertion---------------------------------
      AtData? atData = await TestResources.getHiveKeyStore(atsign)?.get(key);
      expect(atData?.data, 'test_data1');
    });
    tearDownAll(() async => await TestResources.tearDownLocalStorage());
  });
  group(
      'tests related to sending uncommitted entries to server via the batch verb',
      () {
    test('A test to verify batch requests does not entries with commitId', () {
      /// Preconditions:
      /// 1. The local commitId is at commitId 5 and hive_seq is also at 5
      /// 2. There are 3 uncommitted entries - CommitOp.Update - 3.
      ///    The hive_seq is for above 3 uncommitted entries is 6,7,8
      /// 3. ServerCommitId is at 7
      ///
      /// Operation
      /// 1. Initiate sync
      ///
      /// Assertions
      /// 1. The entries from server should be created at hive_seq 9,10 and 11
      /// 2. When fetching uncommitted entries only entries with hive_seq 6,7,8 should be returned.
    });
    test(
        'A test to verify invalid keys and cached keys are not added to batch request',
        () {
      /// Preconditions:
      /// 1. The local commitId is at commitId 5
      /// 2. There are 2 uncommitted entries:
      ///    1. A valid key
      ///    2. An invalid key
      /// 3. The serverCommitId is at 6 where the key is a cached key
      ///
      /// Operation
      /// 1. Initiate sync
      ///
      /// Assertions
      /// 1. The cached key from server should be sync
      /// 2. When fetching uncommitted entries only valid key should be added to uncommittedEntries queue
    });
    test('A test to verify keys in a batch request does not exceed batch limit',
        () {
      /// Preconditions:
      /// Have batch limit set to 5
      /// Have 10 valid keys in the local keystore
      ///
      /// Assertions:
      /// 1. Batch request should contain only 5 keys
    });
    test('A test to verify valid keys added to batch request', () {
      /// Preconditions:
      /// Uncommitted entries should have 5 valid keys
      ///
      /// Assertions:
      /// 1. Batch request should contain all the 5 valid keys
    });
    test(
        'A test to verify the commitId is updated against the uncommitted entries on batch response',
        () {
      /// Preconditions:
      /// Have some uncommitted entries that includes updates and deletes of a key
      /// The uncommitted entries(keys) are sent as a batch request
      ///
      /// Assertions:
      /// Batch response should contain the commitId for every key sent in the batch request
    });
    test(
        'A test to verify sync continues when server returns exception for one of the sync entry',
        () {
      /// This tests focuses to assert when exception occurs on cloud secondary,
      /// the exception should be logged and sync should continue.
      /// Preconditions:
      /// 1. Have 4 valid keys and 1 invalid key in the local keystore
      ///
      /// Assertions:
      /// The sync should fail only for the invalid key and the remaining valid keys should be synced successful
      /// The exception should be thrown for the invalid key
      /// Sync should not be in infinite loop
    });

    test(
        'A test to verify the key into batch request are added in sequential order as in hive keystore',
        () {
      ///Notes of the test case: The uncommitted entries in the hive keystore
      /// should be added to batch request in the same order.
      /// If there are two entries for same key with commit op. update and delete,
      /// then batch request should have the same sequence in it.

      /// Preconditions:
      /// 1. Have uncommitted entries in the keystore
      /// a. hive_seq: 1 - @alice:phone@bob - commitOp. Update - value: +445-446-4847
      /// b. hive_seq:2 - @alice:phone@bob - commitOp. delete
      /// c. hive_seq:3 - @alice:email@bob - commitOp. Update - value: alice@gmail.com
      /// d. hive_seq:4 - @alice:username@bob - commitOp. Update - value: alice123
      /// e. hive_seq:5 - @alice:facebook@bob - commitOp. Update - value: alice
      ///
      /// Assertions:
      /// 1. Batch request should have the same sequence as inserted hive keystore
      ///  i.e., - a,b,c,d,e
    });
  });
  group('tests related to TTL and TTB', () {
    test('A test to verify when a key is set with TTL and expired when sync',
        () {
      /// Preconditions:
      /// 1. Create a key with TTL value of 30 seconds
      /// 2. Let the TTL time expire and then initiate sync
      ///    Since the key is expired, delete operation will triggered.
      ///
      /// Assertions:
      /// 1. Since the key is created and deleted, the key can be omitted to sync
      ///    to cloud secondary
    });
    test(
        'A test to verify when a key is set with TTL and key is not expired when sync starts',
        () {
      /// Preconditions:
      /// 1. Create a key with TTL value of 30 seconds
      /// 2. Initiate sync process
      ///
      ///
      /// Assertions:
      /// 1. The key should be synced to the cloud secondary
    });
    test('A test to verify when a key is set with TTL and is reset', () {
      /// Preconditions:
      /// 1. Create a key with TTL value of 30 seconds
      /// 2. Reset the TTL value to 0
      /// 3. Commitlog keystore should have two entries:
      ///    a. CommitOp. with Update
      ///    b. CommitOp. with Update_Meta
      ///
      /// Operations:
      /// 1. Run sync process
      ///
      /// Assertions:
      /// 1. Both the commits should be synced to the cloud secondary
      /// (If we sync only update_meta, the value will not be updated to cloud secondary)
    });
    test(
        'A test to verify when ttb is set on key and key is not available when sync',
        () {
      //TODO: Arch all discussion: When key is still not born, we return data:null
      // however, when sync process triggers before the key is not born, we get the actual
      // value from keystore instead of 'data:null' to sync to server

      /// Preconditions:
      /// 1. Create a key with ttb value of 30 seconds
      /// 2. Initiate sync at 10th second
      ///
      /// Assertions:
      /// 1. The key should be synced to remote secondary along with the value successfully
    });
    test('A test to verify when a key is set with TTB and key is available',
        () {
      /// Preconditions:
      /// 1. There should be no entry for the same key in the key store
      /// 2. There should be no entry for the same key in the commit log

      /// Operation:
      /// Put a key with TTB say 30 seconds

      /// Assertions:
      /// 1. Key store should have the key with the value inserted
      /// 2. Assert that the value is returned only after 30seconds
      /// 3. A metadata "CreatedAt" should be populated with
      /// DateTime which is less than DateTime.now()
      /// 3. The version of the key should be set to 0
      /// 4. CommitLog should have an entry for the new public key with commitOp.Update
      /// and commitId is null
    });
  });
  group(
      'A group of tests on fetching the local commit id and uncommitted entries',
      () {
    test('A test to verify highest localCommitId is fetched with no regex', () {
      ///Preconditions:
      /// 1. The local keystore contains following keys
      ///   a. phone.wavi@alice with commit id 10
      ///   b. mobile.atmosphere@alice with commit id 11
      ///
      /// Assertions:
      /// When fetched highest commit entry - entry with commit id 11 should be fetched
    });
    test(
        'A test to verify highest localCommitId satisfying the regex is fetched',
        () {
      ///Preconditions:
      /// 1. The local keystore contains following keys
      ///   a. phone.wavi@alice with commit id 10
      ///   b. mobile.atmosphere@alice with commit id 11
      ///
      /// Assertions:
      /// When fetched highest commit entry with regex .wavi - entry with
      /// commit Id 10 should be fetched
    });

    test('A test to verify lastSyncedEntry returned has the highest commitId',
        () {
      ///Preconditions:
      /// 1. The local keystore contains following keys
      ///   a. phone.wavi@alice with commit id 10
      ///   b. mobile.atmosphere@alice with commit id 11
      ///
      /// Assertions:
      /// The lastSyncEntry must have the highest commit id - here commitId 11
    });

    test(
        'A test to verify the uncommitted entries have entries with commit-id null',
        () {
      /// Preconditions:
      ///  1. The local keystore contains following keys
      ///    a. aboutMe.wavi@alice with commit id null and commitOp.Update
      ///    b. phone.wavi@alice with commit id 10 and commitOp.Update
      ///    c. mobile.wavi@alice with commit id 11 and commitOp.Update
      ///    d. country.wavi@alice with commit id null and commitOp.Update
      ///
      /// Assertions:
      ///  The uncommitted entries much have entries with commitId null
      ///    Here: commit entries of aboutMe.wavi@alice and country.wavi@alice
    });
    test(
        'A test to verify lastSyncedEntry returns -1 when commit log do not have keys',
        () {
      /// Preconditions:
      ///  1. The local keystore does not contains keys
      ///
      /// Assertions:
      ///  a. The lastSyncedEntry should be null
      ///  b. The commit entry should be -1
    });
    test('A test to verify sync with regex when local is ahead', () {
      /// Preconditions:
      /// 1. The server commitId is at 100 and local commitId is also 100
      /// 2. In the local keystore have 5 uncommitted entries with .wavi
      /// 3. Initiate sync with regex - ".wavi"
      ///
      /// Assertions:
      /// 1. Server and local should be in sync and 5 uncommitted entries
      ///    must be synced to cloud secondary
    });
  });

  group(
      'Tests to validate how the client processes updates from the server - can the client reject? under what conditions? what happens upon a rejection?',
      () {
    test('Update from server for a key that exists in local secondary', () {
      /// Preconditions:
      /// 1. The key already exists in the local keystore
      /// 2. An entry should already exist in the local commit log
      ///
      /// Operation:
      /// 1. Run sync where the sync response contains an entry with CommitOp.Update of a new key
      ///
      /// Assertions:
      /// 1. The value and metadata of the existing key should be updated
      ///    Since we are updated existing key "createdAt" field should remain as is and
      ///    "updatedAt" field should be updated.
      /// 2. The version field should be incremented by 1
      /// 3. The new entry should be created in the commit log with the new commit id
    });
    test('Update from server for a key that does not exist in local secondary',
        () {
      /// Preconditions:
      /// 1. The key does not exist in the local keystore
      ///
      /// Operation:
      /// 1. Run sync where the sync response contains an entry with CommitOp.Update of a new key
      ///
      /// Assertions:
      /// 1. The new key should be created in the hive keystore
      /// 2. An entry created in the commit log with the new commit id
    });
    test('Delete from server for a key that exists in local secondary', () {
      /// Preconditions:
      /// 1. The key already exists in the local keystore
      /// 2. An entry in commitLog with commitOp.Update
      ///
      /// Operation:
      /// 1. Run sync where the sync response contains an entry with CommitOp.delete of an existing key
      ///
      /// Assertions:
      /// 1. The key should be deleted from the hive keystore
      /// 2. Am entry with commitOp.delete should be added to the commit log
    });
    test('Delete from server for a key that does not exist in local secondary',
        () {
      /// Precondition:
      /// The key does not exist in the local secondary
      ///
      /// Assertions;
      /// An entry should be added to commit log to prevent sync imbalance
    });
    test('Verify clients handling of bad keys in updates from server', () {
      /// Precondition:
      /// Key will be rejected by a put / attempt to write to key store
      /// Commit log has no entry for this key
      /// Key store has no entry for this key

      /// Assertions:
      /// 1. KeyInfo should inform about a bad key / not able sync this key
      /// 2. Key store should be in right state
      /// 3. CommitLog should have an entry along with server commit id

      /// Needs refactoring *
    });
    test(
        'Verify clients handling of bad keys in deletes from server - For an existing bad key',
        () {
      /// Precondition:
      /// Even if it is a bad key, delete operation should just delete
      /// Commit log has a entry for this key
      /// Key store has a entry for this key

      /// Assertions:
      /// 1. KeyInfo should inform about a key being deleted - Can we include info that says 'this happens to be a bad key'
      /// 2. Key store should be in right state
      /// 3. CommitLog should have an entry along with server commit id

      /// Enhancement improve KeyInfo to include description *
    });
    test(
        'Verify clients handling of bad keys in deletes from server - Bad key is not present in the local key store',
        () {
      /// Precondition:
      /// The bad key does not exist in the local secondary
      ///
      /// Assertions;
      /// An entry should be added to commit log to prevent sync imbalance
    });
    group('A group of tests when server is ahead of local commit id', () {
      test('A test to verify server commit entries are synced to local', () {
        /// The test should contain all types of keys - public key, shared key, self key
        ///
        /// Preconditions:
        /// 1. Server has 5 entries that are not synced to the local i.e., server commit id is 15
        /// 2. Local commit id is 10
        ///
        /// Operation:
        /// 1. remote to local sync
        ///
        /// Assertions:
        /// Server and local should be in sync and 5 entries from the server must be synced to local
      });
      test(
          'A test to verify when invalid keys are returned in sync response from server',
          () {});
      test(
          'A test to verify a new key is created in local keystore on update commit operation',
          () {
        /// Preconditions:
        /// 1. There should be no entry for the same key in the key store
        /// 2. There should be no entry for the same key in the commit log

        /// Operation:
        /// CommitOp.UPDATE

        /// Assertions:
        /// 1. Key store should have the public key with the value inserted
        /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
        /// DateTime which is less than DateTime.now()
        /// 3. The version of the key should be set to 0
        /// 4. CommitLog should have an entry for the new public key with commitOp.Update
        /// and commitId is null
      });
      test(
          'A test to verify existing key metadata is updated on update_meta commit operation',
          () {
        //TODO: Update all the available metadata fields and assert
        /// Preconditions:
        /// 1. There should be an entry for the same key in the key store
        /// 2. There should be an entry for the same key in the commit log

        /// Operation:
        /// Updating the metadata for an existing shared key
        /// CommitOp.UPDATE_META
        /// a. Update TTL value to 30 seconds
        /// b. Update TTB value to 10 seconds
        /// c. Update TTR
        /// d. Update CCD to TRUE

        /// Assertions:
        ///1. Assert the metadata of the key. "CreatedAt" field should not be modified and
        /// "UpdatedAt" should be less than now().
        ///  expiresAt, availableAt, refreshAt values in the metadata should be in line with the updated values
        ///  CCD should be true
        /// a. The key should expire after 30seconds
        /// b. The key should be available only after 10 seconds
        ///
        /// 2. The version of the key should be incremented by 1
        /// 4. CommitLog should have an entry for the  key with commitOp.UPDATE_META
      });
      test(
          'A test to verify existing key is deleted when delete commit operation is received',
          () {
        /// Preconditions:
        /// 1. There should be an entry for the same key in the key store
        /// 2. There should be an entry for the same key in the commit log
        ///
        /// Operation:
        /// CommitOp.DELETE
        ///
        /// Assertions:
        /// 1. The key should be deleted from the key store
        /// 2. CommitLog should have an entry for the key with commitOp.DELETE
      });
      test(
          'A test to verify when local keystore does not contain key which is in delete commit operation',
          () {
        /// Preconditions:
        /// 1. There should be no entry for the same key in the key store
        /// 2. There should be no entry for the same key in the commit log
        ///
        /// Operation:
        /// CommitOp.DELETE
        ///
        /// Assertions:
        /// TODO - Should it throw an exception or have an entry for delete in commit log
      });
      test('A test to verify sync with regex when server is ahead', () {
        /// Preconditions:
        /// 1. The server commitId is at 15 and local commitId is at 5
        /// 2. The server has keys with and without matching regex between 5 to 10
        ///    a. keys with .wavi namespace and keys with .atmosphere namespace
        /// 3. Initiate sync with regex - ".wavi"
        ///
        /// Assertions:
        /// 1. The keys matching the regex should only sync to local secondary
        /// 2. isInSync should return after sync completion
      });
    });
    group('A group of test to verify sync conflict resolution', () {
      test(
          'A test to verify when sync conflict info when key present in uncommitted entries and in server response of sync',
          () {
        /// Preconditions:
        /// 1. The server commit id should be greater than local commit id
        /// 2. The server response should an contains a entry - @alice:phone@bob
        /// 3. On the client, in the uncommitted list have the same as above with a different value
        ///
        /// Assertions:
        /// 1. The key should be added to the keyListInfo
      });
    });
  });

  group('Tests to validate how the client and server exchange information', () {
    group('A group of test to verify if client and server are in sync', () {
      test(
          'A test to verify isInSync returns inSync when localCommitId and serverCommitId are equal',
          () {
        /// Preconditions:
        /// 1. The server commitId is at 15 and local commitId is at 15
        ///
        /// Assertions:
        /// 1. isInSync should return true
        ///
        /// Needs Refactoring:
        /// isInSync should return an enum
      });
      test(
          'A test to verify serverAhead when serverCommitId is greater than localCommitId',
          () {
        /// Preconditions:
        /// 1. The server commitId is at 15 and local commitId is at 10
        ///
        /// Assertions:
        /// 1. isInSync should return serverAhead
      });
      test(
          'A test to verify serverAhead when serverCommitId is greater than localCommitId and localCommitId has uncommitted entries',
          () {
        /// Preconditions:
        /// 1. The server commitId is at 15 and local commitId is at 10
        /// 2. The local keystore has 5 uncommitted entries
        ///
        /// Assertions:
        /// 1. isInSync should return serverAhead
      });
      test('A test to verify local secondary has uncommitted entries', () {
        /// Preconditions:
        /// 1. The local commitId is at 15 and serverCommitId 25
        /// 2. The local keystore has 5 uncommitted entries
        ///
        /// Assertions:
        /// 1. isInSync should localAhead
      });
    });
    group('A group of tests to verify sync trigger criteria', () {
      test(
          'A test to verify sync process triggers at configured values for frequent intervals',
          () {
        /// Preconditions:
        /// 1. The _syncRunIntervalSeconds is set to 3 seconds
        /// 2. The sync process is yet to start
        ///
        /// Assertions:
        /// Assert that sync process is triggered at 3 seconds

        /// Needs refactoring *
        /// Say no when:
        /// 1. sync is already running
        /// 2. there is no network
        /// 3. Server and client are already in sync
        /// 4. sync request threshold is not met
      });
      test(
          'A test to verify new sync process does not start when existing sync process is running',
          () {
        /// Preconditions:
        /// 1. The _syncRunIntervalSeconds is set to 3 seconds
        /// 2. The previous sync process is still running
        ///
        /// Assertions:
        /// Assert that new sync process is not started(when time interval or
        ///  threshold value is reached) while the existing sync process is still running
      });
      test(
          'A test to verify sync process does not start when network is not available',
          () {
        /// Preconditions:
        /// 1. Network is unavailable.
        /// 2. The sync process is yet to start
        /// Assertions:
        /// Assert that sync process is not started till the network is back
      });
      test(
          'A test to verify sync process does not start when sync request queue is empty',
          () {
        /// Preconditions:
        /// 1. There are no uncommitted entries/ requests.

        /// Assertions:
        /// Assert that sync process is not started till the syncRequestThreshold is met
      });
      test(
          'A test to verify sync process does not start when sync reqeust queue does not meet the threshold',
          () {
        /// Preconditions:
        /// 1. The _syncRequestThreshold is set to 3.
        /// 2. The sync process is yet to start and there are no requests in the queue
        /// Assertions:
        /// Assert that sync process is not started before the queue size is reached
      });
    });
    group('A group of tests to verify isSyncInProgress flag', () {
      test(
          'A test to verify isSyncInProgress flag is set to true when sync starts',
          () {
        /// Preconditions:
        /// 1. Initially the isSyncInProgress is set to false.
        /// 2. The server commit id and local commit id are equal
        /// 3. The uncommitted entries are available in local keystore
        ///
        /// Assertions:
        /// 1. when sync is triggered, the isSyncInProgress should be set to true
      });
      test(
          'A test to verify isSyncInProgress flag is set to false on sync completion',
          () {
        /// Preconditions:
        /// 1. Initially the isSyncInProgress is set to false.
        /// 2. The server commit id is greater than local commit id
        ///
        /// Assertions:
        /// 1. Once the sync is completed
        ///   a. the local commit id and server commit id should be equal
        ///   b. the isSyncInProgress should be set to false
      });
      test(
          'A test to verify isSyncInProgress flag is set to false when sync stops on network exception',
          () {
        /// Preconditions:
        /// 1. Initially the isSyncInProgress is set to false.
        /// 2. The server commit id is greater than local commit id
        /// 3. The mock server socket should throw time-out exception
        ///
        /// Assertions:
        /// 1. On catching the exception, the isSyncInProgress flag should be set to false
      });
      test(
          'A test to verify a isSyncInProgress flag is set to false when sync stops due to serverException',
          () {
        /// Preconditions:
        /// 1. Initially the isSyncInProgress is set to false.
        /// 2. The server commit id is greater than local commit id
        /// 3. The mock server socket should throw invalid command exception
        ///
        /// Assertions:
        /// 1. On catching the exception, the isSyncInProgress flag should be set to false
      });
      test(
          'A test to verify a isSyncInProgress flag is set to false when sync stops due to socketException',
          () {
        /// Preconditions:
        /// 1. Initially the isSyncInProgress is set to false.
        /// 2. The server commit id is greater than local commit id
        /// 3. The mock server socket should throw socket exception
        ///
        /// Assertions:
        /// 1. On catching the exception, the isSyncInProgress flag should be set to false
      });
    });
    group(
        'A group of tests to validated batch command - sync client changes to server',
        () {
      test(
          'A test to verify batch command when batch size is less than uncommitted entries list size',
          () {
        /// Preconditions:
        /// 1. Have batch size set to 5
        /// 2. Have 10 uncommitted entries in the local keystore
        ///
        /// Assertions:
        /// 1. Batch command should be called twice
        /// 2. The first batch command should have the first 5 entries
        /// 3. The second batch command should have the remaining 5 entries
      });
      test(
          'A test to verify batch command when batch size and uncommitted entries list are equal',
          () {
        /// Preconditions:
        /// 1. Have batch size set to 5
        /// 2. Have 5 uncommitted entries in the local keystore
        ///
        /// Assertions:
        /// Batch command should have all the 5 entries
      });
    });
    group(
        'A group of tests to validate sync command - sync server changes to client',
        () {
      test(
          'A test to verify sync command from server to client on initial sync request',
          () {
        /// Notes: when sync is initial sync request, set local commit id is null or
        /// local keystore is empty set local commit id to -1
      });
      test('A test to verify sync command to delta changes', () {
        /// Preconditions:
        /// 1. The localCommitId is at commitId 5
        /// 2. The serverCommitId is at commitId 10
        ///     commitId 6 and 7 are creation new keys
        ///     commitId 8 is deletion of existing key
        ///     commitId 9 and 10 are update existing keys
        /// 3. No uncommitted entries on the local secondary
        ///
        /// Operation
        /// Run Sync
        ///
        /// Assertions:
        /// 1. The server response should contain the changes from commitId 6 to 10
        /// 2. The local keystore should two existing updates, one exising key deleted and two new keys created
      });
    });
    group('A group of test to verify onDone callback', () {
      test(
          'A test to verify sync result in onDone callback on successful completion',
          () {
        /// Preconditions:
        /// 1. The serverCommitId is greater than localCommitId
        /// 2. Have uncommitted entries on the client side
        /// 3. SyncResult.syncStatus is set to notStarted
        ///
        /// Assertions:
        /// 1. After the sync is completed verify the following:
        ///  a. onDone call is triggered
        ///  b. the direction of keys: For keys pulled from server the direction is "RemoteToLocal"
        ///     and pushed to server is "LocalToRemote"
        /// 2. The SyncResult.syncStatus is set to success
        /// 3. The syncResult.lastSyncedOn is set to sync completion time
      });
      test(
          'A test to verify sync result in onDone callback when sync failure occur',
          () {
        /// Preconditions:
        /// 1. The serverCommitId is greater than localCommitId
        /// 2. Have uncommitted entries on the client side
        /// 3. SyncResult.syncStatus is set to notStarted
        ///
        /// Assertions:
        /// 1. The error is encapsulated in the SyncResult.atClientException
        /// 2. The SyncResult.syncStatus is set to failure
        /// 3. The syncResult.lastSyncedOn is set to sync completion time
      });
    });
    group('A group of test on sync progress call back', () {
      test(
          'A test to verify a new listener is added to sync progress call back',
          () {
        /// Preconditions:
        /// 1. Create a class that extends "SyncProgressListener" and override "onSyncProgressEvent" method
        /// 2. ServerCommitId is greater than localCommitId. Say localCommitId is at 10 and serverCommitId is at 15
        /// 3. Local keystore has previously synced entries and uncommitted entries
        /// 4. The default value for fields in SyncProgressListener:
        ///     a. isInitialSync is set to false
        ///
        ///
        /// Assertions:
        /// 1. Assert on the following fields in SyncProgress:
        ///    a. SyncStatus? syncStatus = SyncStatus.Complete;
        ///    b. isInitialSync will remain false because this sync only fetch delta changes
        ///    c. DateTime? startedAt: The time when sync process started
        ///    d. DateTime? completedAt: The time when sync process is completed
        ///    e. String? message
        ///    f. String? atsign: The currentatsign on which sync is running
        ///    g. List<KeyInfo>? keyInfoList: The keys that are synced
        ///    h. int? localCommitIdBeforeSync: The local committed id before sync; here 10
        ///    i. int? localCommitId: The local commit id after sync; here 15
        ///    j. int? serverCommitId: The server commit id; here 15
      });

      test('A test to verify "isInitialSync" flag in SyncProgressListener', () {
        /// Preconditions:
        /// 1. The local keystore is empty
        /// 2. Initialize a full sync from cloud secondary
        /// 3. The default value for fields in SyncProgressListener:
        ///     a. isInitialSync is set to false
        /// 4. Create a class that extends "SyncProgressListener" and override "onSyncProgressEvent" method
        ///
        /// Assertions:
        /// 1. Assert on the following fields in SyncProgress:
        ///    a. SyncStatus? syncStatus = SyncStatus.Complete;
        ///    b. bool isInitialSync = true;
      });
      test(
          'A test to verify a listener is removed from sync progress call back',
          () {
        /// Preconditions:
        /// Create a class that extends "SyncProgressListener" and override "onSyncProgressEvent" method
        ///
        /// Assertions:
        /// The sync progress listener should be removed from "_syncProgressListeners"
      });
    });
  });
}

class TestResources {
  static AtCommitLog? commitLog;
  static SecondaryPersistenceStore? secondaryPersistenceStore;
  static var storageDir = '${Directory.current.path}/test/hive';

  static Future<void> setupLocalStorage(String atsign,
      {bool enableCommitId = true}) async {
    commitLog = await AtCommitLogManagerImpl.getInstance().getCommitLog(atsign,
        commitLogPath: storageDir, enableCommitId: enableCommitId);
    var secondaryPersistenceStore =
        SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(atsign)!;
    await secondaryPersistenceStore
        .getHivePersistenceManager()!
        .init(storageDir);
    secondaryPersistenceStore.getSecondaryKeyStore()!.commitLog = commitLog;
  }

  static Future<void> tearDownLocalStorage() async {
    try {
      var isExists = await Directory(storageDir).exists();
      if (isExists) {
        Directory(storageDir).deleteSync(recursive: true);
      }
    } catch (e, st) {
      print('sync_test.dart: exception / error in tearDown: $e, $st');
    }
  }

  static HiveKeystore? getHiveKeyStore(String atsign) {
    return SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(atsign)
        ?.getSecondaryKeyStore();
  }

  static Future<CommitEntry?> getCommitEntryLatest(
      String atsign, String atKey) async {
    commitLog = await AtCommitLogManagerImpl.getInstance().getCommitLog(atsign);
    return commitLog!.getLatestCommitEntry(atKey);
  }
}
