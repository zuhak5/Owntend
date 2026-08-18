from pathlib import Path
import re

path = Path("lib/src/features/settings/presentation/settings_screen.dart")
text = path.read_text(encoding="utf-8")


def replace_exact(old: str, new: str, expected: int = 1) -> None:
    global text
    count = text.count(old)
    if count != expected:
        raise SystemExit(
            f"Expected {expected} occurrence(s), found {count}: {old[:90]!r}"
        )
    text = text.replace(old, new)


replace_exact(
    "padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),",
    "padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 112),",
)
replace_exact(
    "horizontal: HkSpacing.space6,",
    "horizontal: SettingsRowGrid.contentInset,",
    expected=4,
)


def add_standalone_tile_grid(title: str, key: str | None = None) -> None:
    global text
    title_pos = text.index(title)
    tile_pos = text.rfind("ListTile(", 0, title_pos)
    content_pos = text.index("contentPadding: EdgeInsets.zero,", tile_pos, title_pos)
    line_start = text.rfind("\n", 0, content_pos) + 1
    indent = text[line_start:content_pos]
    content_end = text.index("\n", content_pos) + 1
    text = (
        text[:content_end]
        + f"{indent}minLeadingWidth: SettingsRowGrid.leadingWidth,\n"
        + f"{indent}horizontalTitleGap: SettingsRowGrid.iconToTextGap,\n"
        + text[content_end:]
    )
    if key is not None:
        title_pos = text.index(title)
        tile_pos = text.rfind("ListTile(", 0, title_pos)
        line_end = text.index("\n", tile_pos) + 1
        tile_line_start = text.rfind("\n", 0, tile_pos) + 1
        child_indent = text[tile_line_start:tile_pos] + "  "
        text = (
            text[:line_end]
            + f"{child_indent}key: const ValueKey('{key}'),\n"
            + text[line_end:]
        )


add_standalone_tile_grid("title: Text(context.l10n.privacyChoices),")
add_standalone_tile_grid("title: Text(context.l10n.adInspector),")
add_standalone_tile_grid(
    "title: Text(context.l10n.weatherLocation),",
    key="settings-weather-row",
)

permission_pattern = re.compile(
    r"(key: const ValueKey\(\s*'settings-permission-education',\s*\),\s*)"
    r"contentPadding: const EdgeInsets\.symmetric\(\s*"
    r"horizontal: HkSpacing\.xs,\s*\),"
)
text, permission_count = permission_pattern.subn(
    r"\1contentPadding: EdgeInsets.zero,", text, count=1
)
if permission_count != 1:
    raise SystemExit("Permission row padding anchor not found")

preferences_start = text.index(
    "_SettingsSubsectionLabel(label: context.l10n.preferences)"
)
preferences_end = text.index("_ReminderSettingsActions(", preferences_start)
segment = text[preferences_start:preferences_end]
segment, switch_key_count = re.subn(
    r"SwitchListTile\(\s*contentPadding: EdgeInsets\.zero,",
    "SwitchListTile(\n"
    "                              key: const ValueKey('settings-alerts-row'),\n"
    "                              contentPadding: EdgeInsets.zero,",
    segment,
    count=1,
)
if switch_key_count != 1:
    raise SystemExit("Representative preference switch not found")

icon_pattern = re.compile(
    r"(secondary|leading): const Icon\(\s*([A-Za-z0-9_.]+),?\s*\),"
)
segment, icon_count = icon_pattern.subn(
    lambda match: (
        f"{match.group(1)}: const _SettingsPlainIcon(icon: {match.group(2)}),"
    ),
    segment,
)
if icon_count < 10:
    raise SystemExit(f"Expected preference icons to normalize, found {icon_count}")
text = text[:preferences_start] + segment + text[preferences_end:]

quiet_end_pattern = re.compile(
    r"trailing: const Icon\(\s*Symbols\.chevron_right_rounded,?\s*\),"
)
text, quiet_end_count = quiet_end_pattern.subn(
    "trailing: Icon(\n"
    "                                        Directionality.of(context) ==\n"
    "                                                TextDirection.rtl\n"
    "                                            ? Symbols.chevron_left_rounded\n"
    "                                            : Symbols.chevron_right_rounded,\n"
    "                                      ),",
    text,
    count=1,
)
if quiet_end_count != 1:
    raise SystemExit(
        f"Expected one physical quiet-hours chevron, found {quiet_end_count}"
    )

grid_marker = "class _SettingsCardHeader extends StatelessWidget {"
grid_class = """class SettingsRowGrid extends StatelessWidget {
  const SettingsRowGrid({required this.child, super.key});

  static const double contentInset = HkSpacing.space20;
  static const double leadingWidth = 40;
  static const double iconToTextGap = HkSpacing.sm;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListTileTheme(
      data: Theme.of(context).listTileTheme.copyWith(
        minLeadingWidth: leadingWidth,
        horizontalTitleGap: iconToTextGap,
      ),
      child: child,
    );
  }
}

"""
replace_exact(grid_marker, grid_class + grid_marker)

panel_pattern = re.compile(
    r"child: IconTheme\(\s*"
    r"data: IconThemeData\(color: scheme\.primary\),\s*"
    r"child: child,\s*\),"
)
text, panel_count = panel_pattern.subn(
    "child: SettingsRowGrid(\n"
    "            child: IconTheme(\n"
    "              data: IconThemeData(color: scheme.primary),\n"
    "              child: child,\n"
    "            ),\n"
    "          ),",
    text,
    count=1,
)
if panel_count != 1:
    raise SystemExit("Settings panel IconTheme anchor not found")

replace_exact(
    "this.size = 40,",
    "this.size = SettingsRowGrid.leadingWidth,",
)

plain_marker = "class _SettingsPreferenceDivider extends StatelessWidget {"
plain_class = """class _SettingsPlainIcon extends StatelessWidget {
  const _SettingsPlainIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: SettingsRowGrid.leadingWidth,
      child: Center(child: Icon(icon)),
    );
  }
}

"""
replace_exact(plain_marker, plain_class + plain_marker)

divider_pattern = re.compile(
    r"return Divider\(\s*height: HkSpacing\.space4,\s*"
    r"indent: 52,\s*endIndent: HkSpacing\.xs,\s*"
    r"color: Theme\.of\(context\)\.colorScheme\.outlineVariant\s*"
    r"\.withValues\(alpha: 0\.72\),\s*\);"
)
text, divider_count = divider_pattern.subn(
    "return Padding(\n"
    "      padding: const EdgeInsetsDirectional.only(\n"
    "        start: SettingsRowGrid.leadingWidth + SettingsRowGrid.iconToTextGap,\n"
    "        end: HkSpacing.xs,\n"
    "      ),\n"
    "      child: Divider(\n"
    "        height: HkSpacing.space4,\n"
    "        color: Theme.of(context).colorScheme.outlineVariant\n"
    "            .withValues(alpha: 0.72),\n"
    "      ),\n"
    "    );",
    text,
    count=1,
)
if divider_count != 1:
    raise SystemExit("Preference divider anchor not found")

effective_padding_pattern = re.compile(
    r"padding: const EdgeInsets\.symmetric\(\s*"
    r"horizontal: HkSpacing\.xs,\s*vertical: HkSpacing\.sm,\s*\),\s*"
    r"child: Column\("
)
text, effective_padding_count = effective_padding_pattern.subn(
    "padding: const EdgeInsets.symmetric(\n"
    "          vertical: HkSpacing.sm,\n"
    "        ),\n"
    "        child: Column(",
    text,
    count=1,
)
if effective_padding_count != 1:
    raise SystemExit("Capability preference padding anchor not found")

path.write_text(text, encoding="utf-8")
