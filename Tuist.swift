import ProjectDescription

let tuist = Tuist(
  fullHandle: "supabitapp/supacode",
  project: .tuist(
    compatibleXcodeVersions: .all,
    swiftVersion: "6.0",
    generationOptions: .options(
      optionalAuthentication: true
    ),
    cacheOptions: .options(
      profiles: .profiles(
        [
          "development": .profile(
            .allPossible,
            except: [
              .named("GhosttyKit"),
            ]
          ),
        ],
        default: .custom("development")
      )
    )
  )
)
