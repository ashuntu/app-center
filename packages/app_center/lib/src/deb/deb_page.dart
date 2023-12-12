import 'dart:async';

import 'package:appstream/appstream.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:packagekit/packagekit.dart';
import 'package:ubuntu_widgets/ubuntu_widgets.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yaru_icons/yaru_icons.dart';
import 'package:yaru_widgets/yaru_widgets.dart';

import '/appstream.dart';
import '/l10n.dart';
import '/layout.dart';
import '/widgets.dart';
import '../packagekit/packagekit_service.dart';
import 'deb_model.dart';

const _kPrimaryButtonMaxWidth = 136.0;

class DebPage extends ConsumerStatefulWidget {
  const DebPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<DebPage> createState() => _DebPageState();
}

class _DebPageState extends ConsumerState<DebPage> {
  StreamSubscription<PackageKitErrorCodeEvent>? _errorSubscription;

  @override
  void initState() {
    super.initState();

    _errorSubscription =
        ref.read(debModelProvider(widget.id)).errorStream.listen(showError);
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _errorSubscription = null;
    super.dispose();
  }

  Future<void> showError(PackageKitServiceError e) => showErrorDialog(
        context: context,
        title: 'PackageKit error: ${e.code}',
        message: e.details,
      );
  @override
  Widget build(BuildContext context) {
    final debModel = ref.watch(debModelProvider(widget.id));
    return debModel.state.when(
      data: (_) => ResponsiveLayoutBuilder(
        builder: (context) => _DebView(
          debModel: debModel,
        ),
      ),
      error: (error, stackTrace) => ErrorWidget(error),
      loading: () => const Center(child: YaruCircularProgressIndicator()),
    );
  }
}

class _DebView extends StatelessWidget {
  const _DebView({required this.debModel});

  final DebModel debModel;

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final l10n = AppLocalizations.of(context);

    final debInfos = <AppInfo>[
      (
        label: Text(l10n.snapPageVersionLabel),
        value: Text(debModel.packageInfo!.packageId.version)
      ),
      if (debModel.component.urls.isNotEmpty)
        (
          label: Text(l10n.snapPageLinksLabel),
          value: Column(
            children: debModel.component.urls
                .where(
                  (url) => [
                    AppstreamUrlType.contact,
                    AppstreamUrlType.homepage,
                  ].contains(url.type),
                )
                .map((url) => Html(
                      data:
                          '<a href="${url.url}">${url.type.localize(l10n)}</a>',
                      style: {'body': Style(margin: Margins.zero)},
                      onLinkTap: (url, attributes, element) =>
                          launchUrlString(url!),
                    ))
                .toList(),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kPagePadding),
      child: Column(
        children: [
          SizedBox(
            width: layout.totalWidth,
            child: _Header(debModel: debModel),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: layout.totalWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppInfoBar(appInfos: debInfos, layout: layout),
                      if (debModel.component.screenshotUrls.isNotEmpty)
                        _Section(
                          header: Text(l10n.snapPageGalleryLabel),
                          child: ScreenshotGallery(
                            title: debModel.component.getLocalizedName(),
                            urls: debModel.component.screenshotUrls,
                            height: layout.totalWidth / 2,
                          ),
                        ),
                      _Section(
                        header: Text(l10n.snapPageDescriptionLabel),
                        child: Html(
                          data: debModel.component.getLocalizedDescription(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DebActionButtons extends ConsumerWidget {
  const _DebActionButtons({required this.debModel});

  final DebModel debModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final primaryAction =
        debModel.isInstalled ? DebAction.remove : DebAction.install;
    final primaryActionButton = SizedBox(
      width: _kPrimaryButtonMaxWidth,
      child: PushButton.elevated(
        onPressed: debModel.activeTransactionId != null
            ? null
            : primaryAction.callback(debModel),
        child: debModel.activeTransactionId != null
            ? Consumer(
                builder: (context, ref, child) {
                  final transaction = ref
                      .watch(transactionProvider(debModel.activeTransactionId!))
                      .whenOrNull(data: (data) => data);
                  return Center(
                    child: SizedBox.square(
                      dimension: 16,
                      child: YaruCircularProgressIndicator(
                        value: (transaction?.percentage ?? 0) / 100.0,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                },
              )
            : Text(primaryAction.label(l10n)),
      ),
    );

    final cancelButton = OutlinedButton(
      onPressed: DebAction.cancel.callback(debModel),
      child: Text(DebAction.cancel.label(l10n)),
    );

    return ButtonBar(
      mainAxisSize: MainAxisSize.min,
      overflowButtonSpacing: 8,
      children: [
        primaryActionButton,
        if (debModel.activeTransactionId != null) cancelButton
      ].whereNotNull().toList(),
    );
  }
}

enum DebAction {
  cancel,
  install,
  remove;

  String label(AppLocalizations l10n) => switch (this) {
        cancel => l10n.snapActionCancelLabel,
        install => l10n.snapActionInstallLabel,
        remove => l10n.snapActionRemoveLabel,
      };

  IconData? get icon => switch (this) {
        remove => YaruIcons.trash,
        _ => null,
      };

  VoidCallback? callback(DebModel model) => switch (this) {
        cancel => model.cancel,
        install => model.install,
        remove => model.remove,
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.debModel});

  final DebModel debModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const YaruBackButton(),
            if (debModel.component.website != null)
              YaruIconButton(
                icon: const Icon(YaruIcons.share),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: debModel.component.website!));
                },
              ),
          ],
        ),
        const SizedBox(height: kPagePadding),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(iconUrl: debModel.component.icon, size: 96),
            const SizedBox(width: 16),
            Expanded(child: AppTitle.fromDeb(debModel.component)),
          ],
        ),
        const SizedBox(height: kPagePadding),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _DebActionButtons(debModel: debModel),
        ),
        const SizedBox(height: 42),
        const Divider(),
      ],
    );
  }
}

class _Section extends YaruExpandable {
  const _Section({required super.header, required super.child})
      : super(
          expandButtonPosition: YaruExpandableButtonPosition.start,
          isExpanded: true,
        );
}
