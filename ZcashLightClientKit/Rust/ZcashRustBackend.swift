//
//  ZcashRustBackend.swift
//  ZcashLightClientKit
//
//  Created by Jack Grigg on 5/8/19.
//  Copyright © 2019 Electric Coin Company. All rights reserved.
//

import Foundation

class ZcashRustBackend: ZcashRustBackendWelding {
    
    static func lastError() -> RustWeldingError? {
        guard let message = getLastError() else { return nil }
        zcashlc_clear_last_error()
        if message.contains("couldn't load Sapling spend parameters") {
            return RustWeldingError.saplingSpendParametersNotFound
        } else if message.contains("is not empty") {
            return RustWeldingError.dataDbNotEmpty
        }
        return RustWeldingError.genericError(message: message)
    }
    
    static func getLastError() -> String? {
        let errorLen = zcashlc_last_error_length()
        if errorLen > 0 {
            let error = UnsafeMutablePointer<Int8>.allocate(capacity: Int(errorLen))
            zcashlc_error_message_utf8(error, errorLen)
            zcashlc_clear_last_error()
            return String(validatingUTF8: error)
        } else {
            return nil
        }
    }
    
    /**
     * Sets up the internal structure of the data database.
     */
    static func initDataDb(dbData: URL) throws {
        let dbData = dbData.osStr()
        guard zcashlc_init_data_database(dbData.0, dbData.1) != 0 else {
            if let error = lastError() {
                throw throwDataDbError(error)
            }
            throw RustWeldingError.dataDbInitFailed(message: "unknown error")
        }
    }
    
    static func isValidShieldedAddress(_ address: String) throws -> Bool {
        guard !address.containsCStringNullBytesBeforeStringEnding() else {
            return false
        }
        
        guard zcashlc_is_valid_shielded_address([CChar](address.utf8CString)) else {
            if let error = lastError() {
                throw error
            }
            return false
        }
        return true
    }
    
    static func isValidTransparentAddress(_ address: String) throws -> Bool {
        guard !address.containsCStringNullBytesBeforeStringEnding() else {
                   return false
        }
        
        guard zcashlc_is_valid_transparent_address([CChar](address.utf8CString)) else {
            if let error = lastError() {
                throw error
            }
            return false
        }
        return true
    }
    
    static func isValidExtendedFullViewingKey(_ key: String) throws -> Bool {
        guard !key.containsCStringNullBytesBeforeStringEnding() else {
            return false
        }
        
        guard zcashlc_is_valid_viewing_key([CChar](key.utf8CString)) else {
            if let error = lastError() {
                throw error
            }
            return false
        }
        return true
    }
    
    static func initAccountsTable(dbData: URL, seed: [UInt8], accounts: Int32) -> [String]? {
        let dbData = dbData.osStr()
        var capacity = UInt(0);
        let extsksCStr = zcashlc_init_accounts_table(dbData.0, dbData.1, seed, UInt(seed.count), accounts, &capacity)
        if extsksCStr == nil {
            return nil
        }
        
        let extsks = UnsafeBufferPointer(start: extsksCStr, count: Int(accounts)).compactMap({ (cStr) -> String? in
            guard let str = cStr else { return nil }
            return String(cString: str)
        })
        zcashlc_vec_string_free(extsksCStr, UInt(accounts), capacity)
        return extsks
    }
    
    static func initAccountsTable(dbData: URL, uvks: [UnifiedViewingKey]) throws -> Bool {
        let dbData = dbData.osStr()
        
        var ffiUvks = [FFIUnifiedViewingKey]()
        for uvk in uvks {
            guard !uvk.extfvk.containsCStringNullBytesBeforeStringEnding() else {
                throw RustWeldingError.malformedStringInput
            }
            guard !uvk.extpub.containsCStringNullBytesBeforeStringEnding() else {
                throw RustWeldingError.malformedStringInput
            }

            let extfvkCStr = [CChar](String(uvk.extfvk).utf8CString)
            
            let extfvkPtr = UnsafeMutablePointer<CChar>.allocate(capacity: extfvkCStr.count)
            extfvkPtr.initialize(from: extfvkCStr, count: extfvkCStr.count)
            
            let extpubCStr = [CChar](String(uvk.extpub).utf8CString)
            let extpubPtr = UnsafeMutablePointer<CChar>.allocate(capacity: extpubCStr.count)
            extpubPtr.initialize(from:extpubCStr, count: extpubCStr.count)
            
            
            ffiUvks.append(FFIUnifiedViewingKey(extfvk: extfvkPtr, extpub: extpubPtr))
        }
        
        
        var result = false
        ffiUvks.withContiguousMutableStorageIfAvailable { p in
            let slice = UnsafeMutablePointer<FFIUVKBoxedSlice>.allocate(capacity: 1)
            slice.initialize(to: FFIUVKBoxedSlice(ptr: p.baseAddress, len: UInt(p.count)))
            
            result = zcashlc_init_accounts_table_with_keys(dbData.0, dbData.1, slice)
            slice.deinitialize(count: 1)
//            slice.deallocate()
        }
        
        defer {
            for uvk in ffiUvks {
                uvk.extfvk.deallocate()
                uvk.extpub.deallocate()
            }
        }
        
        return result
        
    }
//    static func initAccountsTable(dbData: URL, exfvks: [String]) throws -> Bool {
//        let dbData = dbData.osStr()
//        let viewingKeys = exfvks.map { UnsafePointer(strdup($0)) }
//
//        guard exfvks.count > 0 else {
//            throw RustWeldingError.malformedStringInput
//        }
//
//        let res = zcashlc_init_accounts_table_with_keys(dbData.0, dbData.1, viewingKeys, UInt(viewingKeys.count));
//
//        viewingKeys.compactMap({ UnsafeMutablePointer(mutating: $0) }).forEach({ free($0) })
//
//        guard res else {
//            if let error = lastError() {
//                throw error
//            }
//            return false
//        }
//        return res
//
//    }
    
    static func initBlocksTable(dbData: URL, height: Int32, hash: String, time: UInt32, saplingTree: String) throws {
        let dbData = dbData.osStr()
        
        guard !hash.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        guard !saplingTree.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        guard zcashlc_init_blocks_table(dbData.0, dbData.1, height, [CChar](hash.utf8CString), time, [CChar](saplingTree.utf8CString)) != 0 else {
            if let error = lastError() {
                throw error
            }
            throw RustWeldingError.dataDbInitFailed(message: "Unknown Error")
        }
    }
    
    static func getAddress(dbData: URL, account: Int32) -> String? {
        let dbData = dbData.osStr()
        
        guard let addressCStr = zcashlc_get_address(dbData.0, dbData.1, account) else { return nil }
        
        let address = String(validatingUTF8: addressCStr)
        zcashlc_string_free(addressCStr)
        return address
    }
    
    static func getBalance(dbData: URL, account: Int32) -> Int64 {
        let dbData = dbData.osStr()
        return zcashlc_get_balance(dbData.0, dbData.1, account)
    }
    
    static func getVerifiedBalance(dbData: URL, account: Int32) -> Int64 {
        let dbData = dbData.osStr()
        return zcashlc_get_verified_balance(dbData.0, dbData.1, account)
    }
    
    static func getVerifiedTransparentBalance(dbData: URL, address: String) throws -> Int64 {
        guard !address.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        let dbData = dbData.osStr()
        
        return zcashlc_get_verified_transparent_balance(dbData.0, dbData.1, [CChar](address.utf8CString))
    }
    
    static func getTransparentBalance(dbData: URL, address: String) throws -> Int64 {
        guard !address.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        let dbData = dbData.osStr()
        return zcashlc_get_total_transparent_balance(dbData.0, dbData.1, [CChar](address.utf8CString))
    }
    static func clearUtxos(dbData: URL, address: String, sinceHeight: BlockHeight = ZcashSDK.SAPLING_ACTIVATION_HEIGHT) throws -> Int32 {
        let dbData = dbData.osStr()
        
        guard !address.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        let result = zcashlc_clear_utxos(dbData.0, dbData.1, [CChar](address.utf8CString), Int32(sinceHeight))
        
        guard result > 0 else {
            if let error = lastError() {
                throw error
            }
            return result
        }
        return result
    }
    
    static func putUnspentTransparentOutput(dbData: URL, address: String, txid: [UInt8], index: Int, script: [UInt8], value: Int64, height: BlockHeight) throws -> Bool {
        
        let dbData = dbData.osStr()
        
        guard !address.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        guard zcashlc_put_utxo(dbData.0,
                                dbData.1,
                                [CChar](address.utf8CString),
                                txid,
                                UInt(txid.count),
                                Int32(index),
                                script,
                                UInt(script.count),
                                value,
                                Int32(height)) else {
            if let error = lastError() {
                throw error
            }
            return false
        }
        return true
    }
    
    static func downloadedUtxoBalance(dbData: URL, address: String) throws -> WalletBalance {
        let verified = try getVerifiedTransparentBalance(dbData: dbData, address: address)
        let total = try getTransparentBalance(dbData: dbData, address: address)
        return TransparentBalance(verified: verified, total: total, address: address)
    }
    
    static func getReceivedMemoAsUTF8(dbData: URL, idNote: Int64) -> String? {
        let dbData = dbData.osStr()
        
        guard let memoCStr = zcashlc_get_received_memo_as_utf8(dbData.0, dbData.1, idNote) else { return  nil }
        
        let memo = String(validatingUTF8: memoCStr)
        zcashlc_string_free(memoCStr)
        return memo
    }
    
    static func getSentMemoAsUTF8(dbData: URL, idNote: Int64) -> String? {
        let dbData = dbData.osStr()
        
        guard let memoCStr = zcashlc_get_sent_memo_as_utf8(dbData.0, dbData.1, idNote) else { return nil }
        
        let memo = String(validatingUTF8: memoCStr)
        zcashlc_string_free(memoCStr)
        return memo
    }
    
    static func validateCombinedChain(dbCache: URL, dbData: URL) -> Int32 {
        let dbCache = dbCache.osStr()
        let dbData = dbData.osStr()
        return zcashlc_validate_combined_chain(dbCache.0, dbCache.1, dbData.0, dbData.1)
    }
    
    static func getNearestRewindHeight(dbData: URL, height: Int32) -> Int32 {
        let dbData = dbData.osStr()
        return zcashlc_get_nearest_rewind_height(dbData.0, dbData.1, height)
    }
    
    static func rewindToHeight(dbData: URL, height: Int32) -> Bool {
        let dbData = dbData.osStr()
        return zcashlc_rewind_to_height(dbData.0, dbData.1, height)
    }
    
    static func scanBlocks(dbCache: URL, dbData: URL) -> Bool {
        let dbCache = dbCache.osStr()
        let dbData = dbData.osStr()
        return zcashlc_scan_blocks(dbCache.0, dbCache.1, dbData.0, dbData.1) != 0
    }

    static func decryptAndStoreTransaction(dbData: URL, tx: [UInt8]) -> Bool {
        let dbData = dbData.osStr()
        return zcashlc_decrypt_and_store_transaction(dbData.0, dbData.1, tx, UInt(tx.count)) != 0
    }

    static func createToAddress(dbData: URL, account: Int32, extsk: String, to: String, value: Int64, memo: String?, spendParamsPath: String, outputParamsPath: String) -> Int64 {
        let dbData = dbData.osStr()
        let memoBytes = memo ?? ""
        
        return zcashlc_create_to_address(dbData.0,
                                         dbData.1,
                                         account,
                                         [CChar](extsk.utf8CString),
                                         [CChar](to.utf8CString),
                                         value,
                                         [CChar](memoBytes.utf8CString),
                                         spendParamsPath,
                                         UInt(spendParamsPath.lengthOfBytes(using: .utf8)),
                                         outputParamsPath,
                                         UInt(outputParamsPath.lengthOfBytes(using: .utf8)))
    }
    
    static func shieldFunds(dbCache: URL, dbData: URL, account: Int32, tsk: String, extsk: String, memo: String?, spendParamsPath: String, outputParamsPath: String) -> Int64 {
        let dbData = dbData.osStr()
        let memoBytes = memo ?? ""
        
        return zcashlc_shield_funds(dbData.0,
                                    dbData.1,
                                    account,
                                    [CChar](tsk.utf8CString),
                                    [CChar](extsk.utf8CString),
                                    [CChar](memoBytes.utf8CString),
                                    spendParamsPath,
                                    UInt(spendParamsPath.lengthOfBytes(using: .utf8)),
                                    outputParamsPath,
                                    UInt(outputParamsPath.lengthOfBytes(using: .utf8)))
    }
    
    static func deriveExtendedFullViewingKey(_ spendingKey: String) throws -> String? {
        
        guard !spendingKey.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        guard let extsk = zcashlc_derive_extended_full_viewing_key([CChar](spendingKey.utf8CString)) else {
            if let error = lastError() {
                throw error
            }
            return nil
        }
        
        let derived = String(validatingUTF8: extsk)
        
        zcashlc_string_free(extsk)
        return derived
    }
    
    static func deriveExtendedFullViewingKeys(seed: [UInt8], accounts: Int32) throws -> [String]? {
        var capacity = UInt(0);
        guard let extsksCStr = zcashlc_derive_extended_full_viewing_keys(seed, UInt(seed.count), accounts, &capacity) else {
            if let error = lastError() {
                throw error
            }
            return nil
        }
        
        let extsks = UnsafeBufferPointer(start: extsksCStr, count: Int(accounts)).compactMap({ (cStr) -> String? in
            guard let str = cStr else { return nil }
            return String(cString: str)
        })
        zcashlc_vec_string_free(extsksCStr, UInt(accounts), capacity)
        return extsks
    }
    
    static func deriveExtendedSpendingKeys(seed: [UInt8], accounts: Int32) throws -> [String]? {
        var capacity = UInt(0);
        guard let extsksCStr = zcashlc_derive_extended_spending_keys(seed, UInt(seed.count), accounts, &capacity) else {
            if let error = lastError() {
                throw error
            }
            return nil
        }
        
        let extsks = UnsafeBufferPointer(start: extsksCStr, count: Int(accounts)).compactMap({ (cStr) -> String? in
            guard let str = cStr else { return nil }
            return String(cString: str)
        })
        zcashlc_vec_string_free(extsksCStr, UInt(accounts), capacity)
        return extsks
    }
    
    static func deriveUnifiedViewingKeyFromSeed(_ seed: [UInt8], numberOfAccounts: Int) throws -> [UnifiedViewingKey] {
        
        guard let uvks_struct = zcashlc_derive_unified_viewing_keys_from_seed(seed, UInt(seed.count), Int32(numberOfAccounts)) else {
            if let error = lastError() {
                throw error
            }
            throw RustWeldingError.unableToDeriveKeys
        }
        
        let uvks_size = uvks_struct.pointee.len
        guard let uvks_array_pointer = uvks_struct.pointee.ptr, uvks_size > 0 else {
            throw RustWeldingError.unableToDeriveKeys
        }
        var uvks = [UnifiedViewingKey]()
        
        for i: Int in 0 ..< Int(uvks_size) {
            let itemPointer = uvks_array_pointer.advanced(by: i)
            
            guard let extfvk = String(validatingUTF8: itemPointer.pointee.extfvk) else {
                throw RustWeldingError.unableToDeriveKeys
            }
            
            guard let extpub = String(validatingUTF8: itemPointer.pointee.extpub) else {
                throw RustWeldingError.unableToDeriveKeys
            }
            
            uvks.append(UVK(extfvk: extfvk, extpub: extpub))
        }
        
        zcashlc_free_uvk_array(uvks_struct)
        
        return uvks
    }
    
    static func deriveShieldedAddressFromSeed(seed: [UInt8], accountIndex: Int32) throws -> String? {
        guard let zaddrCStr = zcashlc_derive_shielded_address_from_seed(seed, UInt(seed.count), accountIndex) else {
            if let error = lastError() {
                throw error
            }
            return nil
        }
        let zAddr = String(validatingUTF8: zaddrCStr)
        
        zcashlc_string_free(zaddrCStr)
        
        return zAddr
    }
    
    static func deriveShieldedAddressFromViewingKey(_ extfvk: String) throws -> String? {
        guard !extfvk.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        guard let zaddrCStr = zcashlc_derive_shielded_address_from_viewing_key([CChar](extfvk.utf8CString)) else {
            if let error = lastError() {
                throw error
            }
            return nil
        }
        let zAddr = String(validatingUTF8: zaddrCStr)
        
        zcashlc_string_free(zaddrCStr)
        
        return zAddr
    }
    
    static func deriveTransparentAddressFromSeed(seed: [UInt8], account: Int, index: Int) throws -> String? {
        
        guard let tAddrCStr = zcashlc_derive_transparent_address_from_seed(seed, UInt(seed.count), Int32(account), Int32(index)) else {
            if let error = lastError() {
                throw error
            }
            return nil
        }
        
        let tAddr = String(validatingUTF8: tAddrCStr)
        
        return tAddr
    }
    
    static func deriveTransparentPrivateKeyFromSeed(seed: [UInt8], account: Int, index: Int) throws -> String? {
        guard let skCStr = zcashlc_derive_transparent_private_key_from_seed(seed, UInt(seed.count), Int32(account), Int32(index)) else {
            if let error = lastError() {
                throw error
            }
            return nil
        }
        let sk = String(validatingUTF8: skCStr)
        
        return sk
    }
    
    static func derivedTransparentAddressFromPublicKey(_ pubkey: String) throws -> String {
        guard !pubkey.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        
        guard let tAddrCStr = zcashlc_derive_transparent_address_from_public_key([CChar](pubkey.utf8CString)), let tAddr = String(validatingUTF8: tAddrCStr) else {
            if let error = lastError() {
                throw error
            }
            throw RustWeldingError.unableToDeriveKeys
        }
        return tAddr
    }
    
    static func deriveTransparentAddressFromSecretKey(_ tsk: String) throws -> String? {
        
        guard !tsk.containsCStringNullBytesBeforeStringEnding() else {
            throw RustWeldingError.malformedStringInput
        }
        guard let tAddrCStr = zcashlc_derive_transparent_address_from_secret_key([CChar](tsk.utf8CString)) else {
            if let error = lastError() {
                throw error
            }
            return nil
        }
        let tAddr = String(validatingUTF8: tAddrCStr)
        
        return tAddr
    }
    
    static func consensusBranchIdFor(height: Int32) throws -> Int32 {
        let branchId = zcashlc_branch_id_for_height(height)
        
        guard branchId != -1 else {
            throw RustWeldingError.noConsensusBranchId(height: height)
        }
        
        return branchId
    }
    
}

private struct UVK: UnifiedViewingKey {
    var extfvk: ExtendedFullViewingKey
    var extpub: ExtendedPublicKey
}

private extension ZcashRustBackend {
    static func throwDataDbError(_ error: RustWeldingError) -> Error {
        
        if case RustWeldingError.genericError(let message) = error, message.contains("is not empty") {
            return RustWeldingError.dataDbNotEmpty
        }
        return RustWeldingError.dataDbInitFailed(message: error.localizedDescription)
    }
    
}

private extension URL {
    
    func osStr() -> (String, UInt) {
        let path = self.absoluteString
        return (path, UInt(path.lengthOfBytes(using: .utf8)))
    }
    
}

extension String {
    
    /**
     Checks whether this string contains null bytes before it's real ending
     */
    func containsCStringNullBytesBeforeStringEnding() -> Bool {
        self.utf8CString.firstIndex(of: 0) != (self.utf8CString.count - 1)
    }
}
