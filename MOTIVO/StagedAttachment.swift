//
//  StagedAttachment.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 12/09/2025.
//

import Foundation

struct StagedAttachment: Identifiable {
    let id: UUID
    let data: Data
    let kind: AttachmentKind
}
