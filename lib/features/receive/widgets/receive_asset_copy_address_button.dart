import 'package:aqua/config/config.dart';
import 'package:aqua/features/shared/shared.dart';
import 'package:aqua/utils/extensions/context_ext.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';

class ReceiveAssetCopyAddressButton extends HookConsumerWidget {
  const ReceiveAssetCopyAddressButton({
    super.key,
    required this.address,
  });

  final String address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      borderRadius: BorderRadius.all(Radius.circular(8.r)),
      color: Theme.of(context).colors.receiveAddressCopySurface,
      child: InkWell(
        onTap: address.isEmpty
            ? null
            : () async {
                HapticFeedback.mediumImpact();
                await context.copyToClipboard(address);
              },
        splashColor: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.all(Radius.circular(8.r)),
        child: Container(
          width: double.maxFinite,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(8.r)),
          ),
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  address,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onBackground,
                        fontWeight: FontWeight.bold,
                        height: 1.38,
                      ),
                ),
              ),
              SizedBox(width: 24.w),
              SvgPicture.asset(
                Svgs.copy,
                width: 12.r,
                height: 12.r,
                colorFilter: ColorFilter.mode(
                  Theme.of(context).colorScheme.onBackground,
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
