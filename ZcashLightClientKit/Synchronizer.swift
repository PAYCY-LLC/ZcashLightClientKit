//
//  Synchronizer.swift
//  ZcashLightClientKit
//
//  Created by Francisco Gindre on 11/5/19.
//  Copyright © 2019 Electric Coin Company. All rights reserved.
//

import Foundation

/**
Represents errors thrown by a Synchronizer
 */
public enum SynchronizerError: Error {
    case initFailed(message: String)
    case syncFailed
    case connectionFailed(message: Error)
    case generalError(message: String)
    case maxRetryAttemptsReached(attempts: Int)
    case connectionError(status: Int, message: String)
    case networkTimeout
    case uncategorized(underlyingError: Error)
    case criticalError
    case parameterMissing(underlyingError: Error)
}

public enum ShieldFundsError: Error {
    case noUTXOFound
    case insuficientTransparentFunds
    case shieldingFailed(underlyingError: Error)
}

extension ShieldFundsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noUTXOFound:
            return "Could not find UTXOs for the given t-address"
        case .insuficientTransparentFunds:
            return "You don't have enough confirmed transparent funds to perform a shielding transaction."
        case .shieldingFailed(let underlyingError):
            return "Shielding transaction failed. Reason: \(underlyingError)"
        }
    }
}


public protocol WalletBalance {
    var verified: Int64 { get set }
    var total: Int64 { get set }
}

/**
Primary interface for interacting with the SDK. Defines the contract that specific
implementations like SdkSynchronizer fulfill.
*/

public protocol Synchronizer {
    
    
    /**
    Value representing the Status of this Synchronizer. As the status changes, a new
    value will be emitted by KVO
    */
    var status: Status { get }
    
    /**
     A flow of progress values, typically corresponding to this Synchronizer downloading blocks.
     Typically, any non-zero value below 1.0 indicates that progress indicators can be shown and
     a value of 1.0 signals that progress is complete and any progress indicators can be hidden. KVO Compliant
     */
    var progress: Float { get }
    
    /**
     Initialize the internal state with the given Extended Viewing Keys and a wallet birthday
     - Parameter viewingKeys: an array containing the viewing keys to initialize the internal state
     - Parameter walletBirthday: the eldest when the different keys differ in birthday
     - Throws: Initializer Errors and RustWeldingError if fails
     - Note: The subsequent initializations don't have any effect or failure
     */
    func initialize(viewingKeys: [String], walletBirthday: BlockHeight) throws
    
    /**
    Starts this synchronizer within the given scope.
    
    Implementations should leverage structured concurrency and
    cancel all jobs when this scope completes.
    */
    func start(retry: Bool) throws
    
    /**
     Stop this synchronizer. Implementations should ensure that calling this method cancels all
     jobs that were created by this instance.
     */
    func stop() throws
    
    /**
    Gets the address for the given account.
    - Parameter accountIndex: the optional accountId whose address is of interest. By default, the first account is used.
    */
    func getShieldedAddress(accountIndex: Int) -> String
    
    /**
    Sends zatoshi.
    - Parameter spendingKey: the key that allows spends to occur.
    - Parameter zatoshi: the amount of zatoshi to send.
    - Parameter toAddress: the recipient's address.
    - Parameter memo: the optional memo to include as part of the transaction.
    - Parameter accountIndex: the optional account id to use. By default, the first account is used.
    */
    func sendToAddress(spendingKey: String, zatoshi: Int64, toAddress: String, memo: String?, from accountIndex: Int, resultBlock: @escaping (_ result: Result<PendingTransactionEntity, Error>) -> Void)
    
    /**
    Sends zatoshi.
    - Parameter spendingKey: the key that allows spends to occur.
    - Parameter transparentSecretKey: the key that allows to spend transaprent funds
    - Parameter memo: the optional memo to include as part of the transaction.
    - Parameter accountIndex: the optional account id that will be used to shield  your funds to. By default, the first account is used.
    */
    func shieldFunds(spendingKey: String, transparentSecretKey: String, memo: String?, from accountIndex: Int, resultBlock: @escaping (_ result: Result<PendingTransactionEntity, Error>) -> Void)
    
    /**
       Attempts to cancel a transaction that is about to be sent. Typically, cancellation is only
       an option if the transaction has not yet been submitted to the server.
    - Parameter transaction: the transaction to cancel.
    - Returns: true when the cancellation request was successful. False when it is too late.
       */
    
    func cancelSpend(transaction: PendingTransactionEntity) -> Bool
    
    /**
        all outbound pending transactions that have been sent but are awaiting confirmations
     */
    var pendingTransactions: [PendingTransactionEntity] { get }
    /**
     al the transactions that are on the blockchain
     */
    var clearedTransactions: [ConfirmedTransactionEntity] { get }
    /**
     All transactions that are related to sending funds
     */
    var sentTransactions: [ConfirmedTransactionEntity] { get }
    /**
     all transactions related to receiving funds
     */
    var receivedTransactions: [ConfirmedTransactionEntity] { get }
    
    /**
        a repository serving transactions in a paginated manner
     - Parameter kind: Transaction Kind expected from this PaginatedTransactionRepository
     */
    func paginatedTransactions(of kind: TransactionKind) -> PaginatedTransactionRepository
    
    /**
     Returns a list of confirmed transactions that preceed the given transaction with a limit count.
     - Parameters:
       - from: the confirmed transaction from which the query should start from or nil to retrieve from the most recent transaction
       - limit: the maximum amount of items this should return if available
     - Returns: an array with the given Transactions or nil
     
     */
    func allConfirmedTransactions(from transaction: ConfirmedTransactionEntity?, limit: Int) throws -> [ConfirmedTransactionEntity]?
    
    /**
        gets the latest downloaded height from the compact block cache
     */
    func latestDownloadedHeight() throws -> BlockHeight
    
    /**
     Gets the latest block height from the provided Lightwallet endpoint
     */
    func latestHeight(result: @escaping (Result<BlockHeight, Error>) -> Void)
    
    /**
     Gets the latest block height from the provided Lightwallet endpoint
     Blocking
     */
    func latestHeight() throws -> BlockHeight
    
    /**
        Gets the latest UTXOs for the given t-address and caches the result
     */
    func latestUTXOs(address: String, result: @escaping (Result<[UnspentTransactionOutputEntity], Error>) -> Void)
    
    /**
     Gets the latests UTXOs for the given address from the specified height on
     */
    func refreshUTXOs(address: String, from height: BlockHeight, result: @escaping (Result<RefreshedUTXOs,Error>) -> Void)
    
    /**
     gets the latest cached  UTXOs for the given t-address for the given address
     */
    func cachedUTXOs(address: String) throws -> [UnspentTransactionOutputEntity]
    
    /**
     gets the unshielded balance for the given address.
     */
    func latestUnshieldedBalance(address: String, result: @escaping (Result<WalletBalance,Error>) -> Void)
    
    /**
        gets the last stored unshielded balance
     */
    func getTransparentBalance(address: String) throws -> WalletBalance
    
    /**
     gets the shielded total balance (includes verified and unverified balance)
     */
    func getShieldedBalance(accountIndex: Int) -> Int64
    
    /**
     gets the shielded verified balance (anchor is 10 blocks back)
     */
    func getShieldedVerifiedBalance(accountIndex: Int) -> Int64
    
}

/**
 The Status of the synchronizer
 */
public enum Status {
    
    /**
    Indicates that [stop] has been called on this Synchronizer and it will no longer be used.
    */
    case stopped
    
    /**
    Indicates that this Synchronizer is disconnected from its lightwalletd server.
    When set, a UI element may want to turn red.
    */
    case disconnected
    
    /**
    Indicates that this Synchronizer is not yet synced and therefore should not broadcast
    transactions because it does not have the latest data. When set, a UI element may want
    to turn yellow.
    */
    case syncing
    
    /**
    Indicates that this Synchronizer is fully up to date and ready for all wallet functions.
    When set, a UI element may want to turn green.
    */
    case synced
}

/**
 Kind of transactions handled by a Synchronizer
 */
public enum TransactionKind {
    case sent
    case received
    case all
}
