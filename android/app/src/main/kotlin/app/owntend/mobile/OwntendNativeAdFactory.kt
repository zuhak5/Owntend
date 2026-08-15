package app.owntend.mobile

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.google.android.gms.ads.nativead.AdChoicesView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.NativeAdFactory

class OwntendNativeAdFactory(
    private val context: Context,
) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val view = LayoutInflater.from(context)
            .inflate(R.layout.owntend_native_ad, null) as NativeAdView
        val icon = view.findViewById<ImageView>(R.id.owntend_ad_icon)
        val headline = view.findViewById<TextView>(R.id.owntend_ad_headline)
        val body = view.findViewById<TextView>(R.id.owntend_ad_body)
        val advertiser = view.findViewById<TextView>(R.id.owntend_ad_advertiser)
        val callToAction = view.findViewById<TextView>(R.id.owntend_ad_cta)
        val adBadge = view.findViewById<TextView>(R.id.owntend_ad_badge)
        val sponsored = view.findViewById<TextView>(R.id.owntend_ad_sponsored)
        val adChoices = view.findViewById<AdChoicesView>(R.id.owntend_ad_choices)

        view.iconView = icon
        view.headlineView = headline
        view.bodyView = body
        view.advertiserView = advertiser
        view.callToActionView = callToAction
        view.adChoicesView = adChoices

        // Validate a complete palette before mutating the inflated view. An
        // unknown or malformed schema falls back as one unit, so app-owned
        // chrome cannot mix colors from different theme states.
        val palette =
            NativeAdPalette.fromOptions(customOptions)
                ?: NativeAdPalette.fromResources(context)
        applyPalette(
            view = view,
            headline = headline,
            body = body,
            advertiser = advertiser,
            sponsored = sponsored,
            adBadge = adBadge,
            callToAction = callToAction,
            palette = palette,
        )

        headline.text = nativeAd.headline.orEmpty()
        body.bindOptional(nativeAd.body)
        advertiser.bindOptional(nativeAd.advertiser)
        callToAction.bindOptional(nativeAd.callToAction)
        val drawable = nativeAd.icon?.drawable
        if (drawable == null) {
            icon.setImageDrawable(null)
            icon.visibility = View.GONE
        } else {
            icon.setImageDrawable(drawable)
            icon.visibility = View.VISIBLE
        }

        view.setNativeAd(nativeAd)
        return view
    }

    private fun applyPalette(
        view: NativeAdView,
        headline: TextView,
        body: TextView,
        advertiser: TextView,
        sponsored: TextView,
        adBadge: TextView,
        callToAction: TextView,
        palette: NativeAdPalette,
    ) {
        view.background =
            roundedDrawable(
                fillColor = palette.backgroundColor,
                strokeColor = palette.borderColor,
                cornerRadiusDp = 16f,
            )
        headline.setTextColor(palette.headlineColor)
        body.setTextColor(palette.bodyColor)
        advertiser.setTextColor(palette.advertiserColor)
        sponsored.setTextColor(palette.sponsoredColor)
        adBadge.setTextColor(palette.adBadgeTextColor)
        adBadge.background =
            roundedDrawable(
                fillColor = palette.adBadgeBackgroundColor,
                strokeColor = palette.adBadgeTextColor,
                cornerRadiusDp = 4f,
            )
        callToAction.setTextColor(palette.callToActionTextColor)
        callToAction.background =
            roundedDrawable(
                fillColor = palette.callToActionBackgroundColor,
                strokeColor = palette.callToActionBackgroundColor,
                cornerRadiusDp = 8f,
            )
    }

    private fun roundedDrawable(
        fillColor: Int,
        strokeColor: Int,
        cornerRadiusDp: Float,
    ): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fillColor)
            setStroke(dp(1f).toInt().coerceAtLeast(1), strokeColor)
            cornerRadius = dp(cornerRadiusDp)
        }

    private fun dp(value: Float): Float = value * context.resources.displayMetrics.density

    private data class NativeAdPalette(
        val backgroundColor: Int,
        val borderColor: Int,
        val headlineColor: Int,
        val bodyColor: Int,
        val advertiserColor: Int,
        val sponsoredColor: Int,
        val adBadgeBackgroundColor: Int,
        val adBadgeTextColor: Int,
        val callToActionBackgroundColor: Int,
        val callToActionTextColor: Int,
    ) {
        companion object {
            private const val SCHEMA_VERSION = 2
            private val colorPattern = Regex("^#[0-9A-Fa-f]{6}$")

            fun fromOptions(options: Map<String, Any>?): NativeAdPalette? {
                val schemaVersion = options?.get("schemaVersion") as? Number
                if (schemaVersion?.toDouble() != SCHEMA_VERSION.toDouble()) {
                    return null
                }

                fun color(key: String): Int? {
                    val encoded = options[key] as? String ?: return null
                    if (!colorPattern.matches(encoded)) return null
                    return try {
                        Color.parseColor(encoded)
                    } catch (_: IllegalArgumentException) {
                        null
                    }
                }

                return NativeAdPalette(
                    backgroundColor = color("backgroundColor") ?: return null,
                    borderColor = color("borderColor") ?: return null,
                    headlineColor = color("headlineColor") ?: return null,
                    bodyColor = color("bodyColor") ?: return null,
                    advertiserColor = color("advertiserColor") ?: return null,
                    sponsoredColor = color("sponsoredColor") ?: return null,
                    adBadgeBackgroundColor =
                        color("adBadgeBackgroundColor") ?: return null,
                    adBadgeTextColor = color("adBadgeTextColor") ?: return null,
                    callToActionBackgroundColor =
                        color("callToActionBackgroundColor") ?: return null,
                    callToActionTextColor =
                        color("callToActionTextColor") ?: return null,
                )
            }

            fun fromResources(context: Context): NativeAdPalette =
                NativeAdPalette(
                    backgroundColor = context.color(R.color.owntend_ad_surface),
                    borderColor = context.color(R.color.owntend_ad_border),
                    headlineColor = context.color(R.color.owntend_ad_text_primary),
                    bodyColor = context.color(R.color.owntend_ad_text_secondary),
                    advertiserColor = context.color(R.color.owntend_ad_text_secondary),
                    sponsoredColor = context.color(R.color.owntend_ad_text_secondary),
                    adBadgeBackgroundColor =
                        context.color(R.color.owntend_ad_badge_background),
                    adBadgeTextColor = context.color(R.color.owntend_ad_badge_text),
                    callToActionBackgroundColor =
                        context.color(R.color.owntend_ad_cta_background),
                    callToActionTextColor = context.color(R.color.owntend_ad_cta_text),
                )
        }
    }
}

private fun Context.color(resourceId: Int): Int = ContextCompat.getColor(this, resourceId)

private fun TextView.bindOptional(value: String?) {
    text = value.orEmpty()
    visibility = if (value.isNullOrBlank()) View.GONE else View.VISIBLE
}
