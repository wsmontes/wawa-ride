import Foundation

/// A media object reference (Schema.org ImageObject).
///
/// Can represent photos, avatars, route images, and other attachments.
/// The `url` can be a blob CID (ATProto), a local file:// path, a Nostr
/// media tag reference, or an HTTPS URL.
///
/// MediaObject does NOT conform to WawaObject — it is always embedded
/// inside another object (Profile.image, RideEvent attachment, Collection member).
public struct MediaObject: Codable, Sendable, Equatable {
    /// Schema.org type discriminator (always "ImageObject").
    public var type: String = "ImageObject"

    /// The media URL.
    ///
    /// Can be:
    /// - `file://` for local storage
    /// - `https://` for remote hosting
    /// - `blob:` for ATProto CID references
    /// - `nostr:` for Nostr media references
    public var url: String?

    /// Content size in bytes.
    public var contentSize: Int?

    /// MIME type.
    ///
    /// Examples: `"image/jpeg"`, `"image/heic"`, `"image/png"`.
    public var encodingFormat: String?

    /// Image width in pixels.
    public var width: Int?

    /// Image height in pixels.
    public var height: Int?

    public init(
        url: String? = nil,
        contentSize: Int? = nil,
        encodingFormat: String? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.url = url
        self.contentSize = contentSize
        self.encodingFormat = encodingFormat
        self.width = width
        self.height = height
    }
}
