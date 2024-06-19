import 'dart:async';

import 'package:aqua/data/data.dart';
import 'package:aqua/features/address_validator/address_validation.dart';
import 'package:aqua/features/send/providers/providers.dart';
import 'package:aqua/features/settings/manage_assets/manage_assets.dart';
import 'package:aqua/features/shared/shared.dart';
import 'package:aqua/features/swap/swap.dart';
import 'package:aqua/features/transactions/transactions.dart';
import 'package:aqua/logger.dart';

final pegProvider =
    AutoDisposeAsyncNotifierProvider<PegNotifier, PegState>(PegNotifier.new);

class PegNotifier extends AutoDisposeAsyncNotifier<PegState> {
  @override
  FutureOr<PegState> build() => const PegState.empty();

  Future<void> requestVerification(SwapStartPegResponse response) async {
    final order = response.result!;
    final isLiquid =
        await ref.read(addressParserProvider).isValidAddressForAsset(
              asset: Asset.liquid(),
              address: order.pegAddress,
            );
    final assets = ref.read(assetsProvider).asData?.value ?? [];
    final asset = assets.firstWhere((e) => isLiquid ? e.isLBTC : e.isBTC);
    final input = ref.read(sideswapInputStateProvider);
    final statusStream = ref.read(sideswapStatusStreamResultStateProvider);

    final txn = await createPegGdkTransaction(
      asset: asset,
      pegAddress: order.pegAddress,
      isSendAll: input.isSendAll,
      deliverAmountSatoshi: input.deliverAmountSatoshi,
    );

    if (txn == null) {
      logger.d('[PEG] Transaction cannot be created');
      final error = PegGdkTransactionException();
      state = AsyncValue.error(error, StackTrace.current);
      throw error;
    }

    final fee = txn.fee!;
    final inputAmount = input.deliverAmountSatoshi;
    final amountMinusOnchainFee = inputAmount - fee;
    final amountMinusSideSwapFee =
        SideSwapFeeCalculator.subtractSideSwapFeeForPegDeliverAmount(
            amountMinusOnchainFee, input.isPegIn, statusStream);

    logger.d(
        "[Peg] Verifying Order - Input Amount: $inputAmount - Onchain Fee: $fee - Amount (minus onchain fee): $amountMinusOnchainFee - Amount (minus sideswap fee): $amountMinusSideSwapFee");

    if (fee > inputAmount) {
      logger.d('[PEG] Fee ($fee) exceeds amount ($inputAmount)');
      final error = PegGdkFeeExceedingAmountException();
      state = AsyncValue.error(error, StackTrace.current);
      throw error;
    }

    final data = SwapPegReviewModel(
      asset: asset,
      order: order,
      transaction: txn,
      inputAmount: inputAmount,
      feeAmount: fee,
      sendTxAmount: amountMinusOnchainFee,
      receiveAmount: amountMinusSideSwapFee.toInt(),
      isSendAll: input.isSendAll,
    );
    state = AsyncData(PegState.pendingVerification(data: data));
  }

  Future<void> executeTransaction() async {
    final currentState = state.asData?.value;
    if (currentState is PegStateVerify) {
      final data = currentState.data;
      final amount = data.sendTxAmount;
      final statusStream = ref.read(sideswapStatusStreamResultStateProvider);

      final minBtcAmountSatoshi = statusStream?.minPegInAmount;
      final minLbtcAmountSatoshi = statusStream?.minPegOutAmount;
      if (minBtcAmountSatoshi != null &&
          data.asset.isBTC &&
          amount < minBtcAmountSatoshi) {
        logger.d('[PEG] BTC amount too low (min: $minBtcAmountSatoshi))');
        final error = PegSideSwapMinBtcLimitException();
        state = AsyncValue.error(error, StackTrace.current);
        throw error;
      }
      if (minLbtcAmountSatoshi != null &&
          data.asset.isLBTC &&
          amount < minLbtcAmountSatoshi) {
        logger.d('[PEG] L-BTC amount too low (min: $minLbtcAmountSatoshi))');
        final error = PegSideSwapMinLBtcLimitException();
        state = AsyncValue.error(error, StackTrace.current);
        throw error;
      }

      logger.d(
          "[Sideswap][Peg] created tx - asset: ${data.asset.ticker} - amount: $amount - isSendAll: ${data.isSendAll} - pegAddress: ${data.order.pegAddress} - reply: ${data.transaction}");

      final transaction =
          await signPegGdkTransaction(data.transaction, data.asset);
      if (transaction == null) {
        final error = PegGdkTransactionException();
        state = AsyncValue.error(error, StackTrace.current);
        throw error;
      } else {
        await ref
            .read(transactionStorageProvider.notifier)
            .save(TransactionDbModel(
              txhash: transaction.txhash!,
              assetId: data.asset.id,
              type: ref.read(sideswapInputStateProvider).isPegIn
                  ? TransactionDbModelType.sideswapPegIn
                  : TransactionDbModelType.sideswapPegOut,
              serviceOrderId: data.order.orderId,
              serviceAddress: data.order.pegAddress,
            ));
        state = const AsyncValue.data(PegState.success());
      }
    } else {
      throw Exception('Invalid state: $state');
    }
  }

  Future<GdkNewTransactionReply?> createPegGdkTransaction({
    required Asset asset,
    required String pegAddress,
    required bool isSendAll,
    required int deliverAmountSatoshi,
    bool relayErrors = true,
  }) async {
    try {
      final network =
          asset.isBTC ? ref.read(bitcoinProvider) : ref.read(liquidProvider);

      final addressee = GdkAddressee(
        assetId: asset.isBTC ? null : asset.id,
        address: pegAddress,
        satoshi: deliverAmountSatoshi,
      );

      int feeRatePerKb;
      final networkType =
          asset.isBTC ? NetworkType.bitcoin : NetworkType.liquid;

      if (networkType == NetworkType.bitcoin) {
        final feeRatesMap = ref.watch(pegFeeRatesProvider).asData?.value ?? {};
        final feeRatePerVb =
            feeRatesMap.entries.firstWhere((entry) => entry.key.isBTC).value;
        feeRatePerKb = (feeRatePerVb * 1000.0).ceil();
      } else {
        feeRatePerKb = liquidFeeRatePerKb;
      }

      final transaction = GdkNewTransaction(
        addressees: [addressee],
        feeRate: feeRatePerKb,
        sendAll: isSendAll,
        utxoStrategy: GdkUtxoStrategyEnum.defaultStrategy,
      );

      return await network.createTransaction(transaction);
    } on GdkNetworkInsufficientFunds {
      logger.d('[PEG] Insufficient funds');
      if (relayErrors) {
        final error = PegGdkInsufficientFeeBalanceException();
        state = AsyncValue.error(error, StackTrace.current);
        throw error;
      }
    } catch (e) {
      if (relayErrors) {
        logger.e('[PEG] create gdk tx error: $e');
        final error = PegGdkTransactionException();
        state = AsyncValue.error(error, StackTrace.current);
        throw error;
      }
    }

    return null;
  }

  Future<GdkNewTransactionReply?> signPegGdkTransaction(
    GdkNewTransactionReply reply,
    Asset asset,
  ) async {
    try {
      final network =
          asset.isBTC ? ref.read(bitcoinProvider) : ref.read(liquidProvider);

      final signedReply = await network.signTransaction(reply);
      if (signedReply == null) {
        throw PegGdkTransactionException();
      }

      final response = await network.sendTransaction(signedReply);
      if (response == null) {
        throw PegGdkTransactionException();
      }

      return response;
    } catch (e) {
      logger.e('[PEG] sign/send gdk tx error: $e');
      final error = PegGdkTransactionException();
      state = AsyncValue.error(error, StackTrace.current);
      throw error;
    }
  }
}

sealed class PegError implements Exception {}

class PegGdkInsufficientFeeBalanceException extends PegError {}

class PegGdkFeeExceedingAmountException extends PegError {}

class PegGdkTransactionException extends PegError {}

class PegSideSwapMinBtcLimitException extends PegError {}

class PegSideSwapMinLBtcLimitException extends PegError {}
