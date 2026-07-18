import Foundation

/// Build-time connector configuration.
///
/// OAuth client IDs are NOT secrets — every shipped app embeds its own in
/// the binary. This is the standard practice that makes "Sign in with
/// Google" a one-tap experience for users; the registration behind it is a
/// one-time developer task (see docs/CONNECTORS.md).
///
/// When `googleClientID` is empty, the Google Drive connect sheet falls
/// back to asking for one — useful for other developers cloning this repo.
enum ConnectorSecrets {
    static let googleClientID = "335267564860-lfrauq7acq48um299pbpasnn4kceqj9v.apps.googleusercontent.com"
}
