# Tangent architecture

## Directory responsibilities

- `Tangent/App/` creates the SwiftData container and injects application dependencies.
- `Tangent/DesignSystem/` owns shared semantic colours and future reusable UI tokens.
- `Tangent/Features/Record/` and `Tangent/Features/Library/` own their respective SwiftUI views and feature logic.
- `Tangent/Domain/` contains persistence-independent app models and service protocols.
- `Tangent/Data/` contains SwiftData models, domain conversions, container setup, and the `NoteStore` implementation.
- `Tangent/Services/Audio/` and `Tangent/Services/Speech/` contain concrete media service implementations.
- `Tangent/Services/Intelligence/` contains the on-device language model: loading, downloads, summaries and insights. It is the only place that imports MLX.

## Dependency direction

Features depend on domain models and protocols. `Data` and `Services` implement those protocols, and `App` composes the implementations. Domain code does not import SwiftData, and feature code must not access `ModelContext` or persistence records directly.

## Persistence

`TangentModelContainer` owns the schema for patient profiles, prompts, questions, diary entries, and insights. `SwiftDataNoteStore` provides async CRUD-style operations and converts between SwiftData records and domain values. Diary questions and populated prompt text are stored as historical snapshots.

Use an in-memory container for tests and previews. The app uses the default local SwiftData store; no data leaves the device.

## On-device generation

`HealthLanguageModel` and `ModelCatalog` are domain protocols. Features use
these protocols; only `Services/Intelligence` imports MLX. `App` injects
`MLXHealthLanguageModel` on devices and `UnavailableHealthLanguageModel` on the
simulator. The simulator can exercise diary workflows without model inference.

Recording saves an entry, then `DailyTangentDetailsViewModel` transcribes the
recording and requests one short summary. It stores the sentence and its filled
prompt, and reuses the saved summary when the entry is reopened. There is no
background second generation task. Transcripts remain available in daily details.

`InsightsViewModel` filters entries by the selected date range and converts
nonempty short summaries to `DiarySummary` values. The language-model service
receives only dates and summary text. `PromptTemplate` orders these by date
and builds the insights prompt; neither transcripts nor patient profiles are
inputs to insight generation. Entries without summaries are skipped.

`MLXHealthLanguageModel` holds one loaded model. `MLXModelCatalog` downloads
weights to Application Support when requested in Settings. Diary content and
inference stay on the device; network access is used to download model weights.

The current diary schema stores `summaryShort` only. SwiftData's automatic
migration removes the obsolete attribute from existing stores; an on-disk test
verifies this without deleting diary entries. `PromptSeeder` also removes the
retired built-in template while preserving custom prompts.

## Adding workflows

Keep persistence models and `ModelContext` in `Data`. Inject domain protocols
through `AppDependencies`; views and view models must not import SwiftData or
MLX to implement a workflow. Add tests for persistence changes and feature
behaviour in the existing test targets.
