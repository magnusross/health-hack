# Tangent architecture

## Directory responsibilities

- `Tangent/App/` creates the SwiftData container and injects application dependencies.
- `Tangent/DesignSystem/` owns shared semantic colours and future reusable UI tokens.
- `Tangent/Features/Record/` and `Tangent/Features/Library/` own their respective SwiftUI views and feature logic.
- `Tangent/Domain/` contains persistence-independent app models and service protocols.
- `Tangent/Data/` contains SwiftData models, domain conversions, container setup, and the `NoteStore` implementation.
- `Tangent/Services/Audio/` and `Tangent/Services/Speech/` contain concrete media service implementations.

## Dependency direction

Features depend on domain models and protocols. `Data` and `Services` implement those protocols, and `App` composes the implementations. Domain code does not import SwiftData, and feature code must not access `ModelContext` or persistence records directly.

## Persistence

`TangentModelContainer` owns the schema for patient profiles, prompts, questions, diary entries, and insights. `SwiftDataNoteStore` provides async CRUD-style operations and converts between SwiftData records and domain values. Diary questions and populated prompt text are stored as historical snapshots.

Use an in-memory container for tests and previews. The app uses the default local SwiftData store; no data leaves the device.

## Adding workflows

Inject `NoteStore`, `AudioRecorder`, and `Transcriber` from `AppDependencies`. Add real recording and transcription implementations under their service directories and replace the unavailable placeholders in `TangentApp`. New workflows should add domain operations when needed and use protocols rather than importing SwiftData into feature code.
