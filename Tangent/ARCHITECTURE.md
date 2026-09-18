# Tangent architecture

## Directory responsibilities

- `Tangent/App/` creates the SwiftData container and injects application dependencies.
- `Tangent/DesignSystem/` owns shared semantic colours and future reusable UI tokens.
- `Tangent/Features/Record/` and `Tangent/Features/Library/` own their respective SwiftUI views and feature logic.
- `Tangent/Domain/` contains persistence-independent app models and service protocols.
- `Tangent/Data/` contains SwiftData models, domain conversions, container setup, and the `NoteStore` implementation.
- `Tangent/Services/Audio/` and `Tangent/Services/Speech/` contain concrete media service implementations.
- `Tangent/Services/LanguageModel/` contains the mock-backed insights service.
- `Tangent/Services/Intelligence/` contains the on-device language model: loading, downloads and summary generation. It is the only place that imports MLX.

## Dependency direction

Features depend on domain models and protocols. `Data` and `Services` implement those protocols, and `App` composes the implementations. Domain code does not import SwiftData, and feature code must not access `ModelContext` or persistence records directly.

## Persistence

`TangentModelContainer` owns the schema for patient profiles, prompts, questions, diary entries, and insights. `SwiftDataNoteStore` provides async CRUD-style operations and converts between SwiftData records and domain values. Diary questions and populated prompt text are stored as historical snapshots.

Use an in-memory container for tests and previews. The app uses the default local SwiftData store; no data leaves the device.

## On-device summaries

Summaries are written by a 4-bit Gemma 3 1B or MedGemma 1.5 4B running on the
device's GPU through MLX. Nothing is sent anywhere; the only network traffic is
the model download, which the user starts in Settings.

`SummaryGenerator` and `ModelCatalog` are domain protocols, so features talk
about models without importing MLX. `SummaryModelID` names the two models,
`SummaryPromptTemplate` holds the prompt and fills its `{transcript}` and
`{user_profile}` placeholders, and `GeneratedSummary` carries the two summaries
plus the filled prompt that `DIARY.prompt_text` persists.

`MLXSummaryGenerator` is an actor holding at most one loaded model — the two
together would exhaust memory on iOS. The model is asked for JSON, and
`SummaryJSON` pulls the object out of a noisy completion; one retry follows an
unparseable answer, after which generation fails explicitly rather than
inventing a summary. `MLXModelCatalog` downloads weights into Application
Support (not Caches, which iOS may purge) and remembers the chosen model.

MLX needs a Metal GPU, so on the Simulator `TangentApp` injects
`UnavailableSummaryGenerator` and summaries fail with a clear message.

Generation runs on the daily details screen, after transcription, in
`DailyTangentDetailsViewModel`. A diary entry is saved when the recording stops
with its summaries empty; they are filled in once the model has written them.

## Adding workflows

Inject `NoteStore`, `AudioRecorder`, `Transcriber`, and `HealthLanguageModel` from `AppDependencies`. The app currently injects `MockHealthLanguageModel`, which keeps Simulator development independent of MLX and exposes its mock state to the UI. A future MLX implementation should be the only type that imports MLX and can replace the mock in `TangentApp` when model files are available. New workflows should add domain operations when needed and use protocols rather than importing SwiftData into feature code.
