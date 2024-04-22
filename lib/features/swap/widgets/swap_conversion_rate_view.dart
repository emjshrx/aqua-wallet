import 'package:aqua/config/config.dart';
import 'package:aqua/features/shared/shared.dart';
import 'package:aqua/features/swap/swap.dart';

class SwapConversionRateView extends HookConsumerWidget {
  const SwapConversionRateView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = ref.watch(sideswapConversionRateAmountProvider);
    final error = ref.watch(swapValidationsProvider(context));
    final isLoading = ref.watch(swapLoadingIndicatorStateProvider) ==
        const SwapProgressState.connecting();

    if (isLoading) {
      return Container(
        height: 34.h,
        margin: EdgeInsets.symmetric(vertical: 12.h),
        padding: EdgeInsets.symmetric(vertical: 9.h),
        child: const Text('1 BTC = 1 L-BTC'),
      );
    }

    return Container(
      height: 34.h,
      margin: EdgeInsets.symmetric(vertical: 12.h),
      padding: EdgeInsets.all(1.h),
      child: amount == null || error != null
          ? const SizedBox.shrink()
          : BoxShadowContainer(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colors.conversionRateSwapScreenColor,
                borderRadius: BorderRadius.circular(6.r),
                boxShadow: [
                  Theme.of(context).swapScreenRateConversionBoxShadows,
                ],
              ),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 9.h),
              child: Text(
                amount,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13.sp,
                      color: Theme.of(context)
                          .colors
                          .swapConversionRateViewTextColor,
                    ),
              ),
            ),
    );
  }
}
