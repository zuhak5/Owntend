part of 'assets_presentation.dart';

Future<void> addPhotoToAsset(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
) async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 82,
    maxWidth: 1800,
  );
  if (image == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  try {
    await ref.read(assetRepositoryProvider).addPhoto(asset.id, image.path);
    if (!context.mounted) {
      return;
    }
    hk_ui.showToast(context, content: Text(context.l10n.photoSaved));
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          failureMessage(context, error, fallback: AppFailureCode.photoSave),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }
}
