import Foundation

nonisolated struct GoogleDriveUploader: Sendable {
    private let folderName = "Vigil"

    func upload(
        fileURL: URL,
        createdAt: Date,
        accessToken: String
    ) async throws {
        let folder = try await findOrCreateFolder(accessToken: accessToken)
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let fileSize, fileSize > 0 else {
            throw GoogleDriveUploadError.unreadableFile
        }

        let sessionURL = try await createResumableSession(
            folderID: folder.id,
            filename: remoteFilename(for: createdAt),
            fileSize: fileSize,
            accessToken: accessToken
        )

        var request = URLRequest(url: sessionURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        try validate(response: response, data: data)
    }

    func folderURL(accessToken: String) async throws -> URL {
        let folder = try await findOrCreateFolder(accessToken: accessToken)
        guard let link = folder.webViewLink,
              let url = URL(string: link) else {
            throw GoogleDriveUploadError.missingFolderLink
        }
        return url
    }

    private func findOrCreateFolder(accessToken: String) async throws -> DriveFile {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")
        components?.queryItems = [
            URLQueryItem(
                name: "q",
                value: "name = '\(folderName)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
            ),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name,webViewLink)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]
        guard let url = components?.url else {
            throw GoogleDriveUploadError.invalidResponse
        }

        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        if let existing = try JSONDecoder().decode(DriveFileList.self, from: data).files.first {
            return existing
        }

        return try await createFolder(accessToken: accessToken)
    }

    private func createFolder(accessToken: String) async throws -> DriveFile {
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files?fields=id,name,webViewLink") else {
            throw GoogleDriveUploadError.invalidResponse
        }

        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": folderName,
            "mimeType": "application/vnd.google-apps.folder"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(DriveFile.self, from: data)
    }

    private func createResumableSession(
        folderID: String,
        filename: String,
        fileSize: Int,
        accessToken: String
    ) async throws -> URL {
        guard let url = URL(
            string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name"
        ) else {
            throw GoogleDriveUploadError.invalidResponse
        }

        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("video/quicktime", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": filename,
            "mimeType": "video/quicktime",
            "parents": [folderID]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        guard let httpResponse = response as? HTTPURLResponse,
              let location = httpResponse.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: location) else {
            throw GoogleDriveUploadError.missingUploadSession
        }
        return sessionURL
    }

    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveUploadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(GoogleAPIErrorEnvelope.self, from: data))?
                .error.message ?? "Google Drive returned error \(httpResponse.statusCode)."
            throw GoogleDriveUploadError.service(message)
        }
    }

    private func remoteFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Vigil_\(formatter.string(from: date)).mov"
    }
}

nonisolated private struct DriveFileList: Decodable, Sendable {
    let files: [DriveFile]
}

nonisolated private struct DriveFile: Decodable, Sendable {
    let id: String
    let webViewLink: String?
}

nonisolated private struct GoogleAPIErrorEnvelope: Decodable, Sendable {
    nonisolated struct APIError: Decodable, Sendable {
        let message: String
    }

    let error: APIError
}

nonisolated enum GoogleDriveUploadError: LocalizedError, Sendable {
    case invalidResponse
    case unreadableFile
    case missingUploadSession
    case missingFolderLink
    case service(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Google Drive returned an unreadable response."
        case .unreadableFile:
            "The completed recording could not be read for upload."
        case .missingUploadSession:
            "Google Drive did not create an upload session."
        case .missingFolderLink:
            "Google Drive did not provide a link to the Vigil folder."
        case .service(let message):
            message
        }
    }
}
