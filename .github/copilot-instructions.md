# CancelKnife Plugin - Copilot Coding Agent Instructions

## Repository Overview
This repository contains a SourcePawn plugin for SourceMod called "CancelKnife" (v1.7.0). The plugin allows server administrators to revert knife actions in zombie-themed Source engine games, restoring affected players to their previous states (position, health, equipment, team status).

**Key Functionality:**
- Tracks knife events between zombies and humans
- Provides admin menu system to cancel/revert knife actions
- Restores player states (position, health, armor, weapons, grenades)
- Integrates with zombie-themed game modes
- Supports admin punishment systems (slaying, banning)

## Technical Environment

### Core Technologies
- **Language**: SourcePawn (.sp files)
- **Platform**: SourceMod 1.11+ (currently using 1.11.0-git6934)
- **Build System**: sourceknight (Python-based dependency management and building)
- **Compiler**: SourcePawn compiler (spcomp) via sourceknight
- **CI/CD**: GitHub Actions with automatic releases

### Project Structure
```
/addons/sourcemod/scripting/
  └── CancelKnife.sp          # Main plugin source file

/.github/
  ├── workflows/ci.yml        # CI/CD pipeline
  └── dependabot.yml         # Dependency updates

/sourceknight.yaml          # Build configuration and dependencies
/.gitignore                # Git ignore rules
```

## Dependencies & Integration

### Required Dependencies (via sourceknight.yaml)
- **sourcemod**: Core SourceMod framework (1.11.0-git6934)
- **multicolors**: Chat color formatting library
- **zombiereloaded**: Zombie game mode framework
- **KnockbackRestrict**: Knockback control system

### Optional Dependencies
- **knifemode**: Knife-only game mode support (conditionally compiled)

### Integration Points
- **ZombieReloaded**: `ZR_OnClientInfected`, `ZR_IsClientZombie`, `ZR_IsClientHuman`, `ZR_HumanClient`
- **KnockbackRestrict**: `KR_ClientStatus`, `KR_DisplayLengthsMenu`, `KR_BanClient`
- **MultiColors**: `CSetPrefix`, `CPrintToChat`, `CPrintToChatAll`
- **KnifeMode**: `KnifeMode_OnToggle` (optional)

## Code Style & Standards

### SourcePawn Conventions
- **Indentation**: 4 spaces (configured as tabs)
- **Variables**: camelCase for local variables, PascalCase for functions
- **Global Variables**: Prefix with `g_`
- **Constants**: ALL_CAPS with underscores
- **Required Pragmas**: `#pragma semicolon 1` and `#pragma newdecls required`

### Memory Management
- **Critical**: Use `delete` for Handle cleanup, never check for null before delete
- **Avoid**: `.Clear()` on StringMap/ArrayList - creates memory leaks
- **Prefer**: `delete` and recreate containers instead of clearing
- **Pattern**: Store entity references with `EntIndexToEntRef` for validation

### Data Structures
- **Methodmaps**: Used for structured data (`CKnife`, `CKnifeRevert`, `PlayerData`)
- **Collections**: ArrayList for dynamic collections, StringMap for key-value storage
- **Arrays**: Fixed-size arrays for player data (`g_PlayerData[MAXPLAYERS + 1]`)

## Key Code Patterns

### Plugin Architecture
```sourcepawn
// Main data structures
enum struct CKnife {
    int attackerUserId;
    int victimUserId;
    char attackerName[32];
    char victimName[32];
    float victimOrigin[3];
    int time;
    ArrayList deadPeople;  // CKnifeRevert entries
}

enum struct PlayerData {
    char weaponPrimaryStr[WEAPONS_MAX_LENGTH];
    // ... other player state data
    void Reset() { /* cleanup implementation */ }
}
```

### Event Handling Pattern
- **Pre-hook**: `Event_PlayerHurt` with `EventHookMode_Pre` for damage detection
- **Post-hook**: `ZR_OnClientInfected` for infection chain tracking
- **Damage Hook**: `SDKHook_OnTakeDamage` for health state preservation

### Admin Command Pattern
```sourcepawn
RegAdminCmd("sm_cknife", Command_CKnife, ADMFLAG_KICK, "Description");
// Always include permission flags and descriptions
```

## Build & Development Workflow

### Local Development Setup
1. **Install sourceknight**: `python3 -m pip install sourceknight`
2. **Build plugin**: `sourceknight build` (from project root)
3. **Output location**: `.sourceknight/package/addons/sourcemod/plugins/`

### CI/CD Pipeline
- **Trigger**: Push, PR, or manual dispatch
- **Build**: Uses `maxime1907/action-sourceknight@v1`
- **Package**: Creates `.tar.gz` with compiled plugins
- **Release**: Automatic releases on tags and main branch

### Testing Strategy
- **Manual Testing**: Deploy to development server with zombie game mode
- **Scenarios**: Test knife events, admin reversion, state restoration
- **Validation**: Verify player position, health, equipment restoration
- **Integration**: Test with all dependent plugins active

## Configuration & ConVars

### Plugin ConVars (auto-generated config)
```sourcepawn
sm_cknife_time "15"                    // Revert time window (seconds)
sm_cknife_slay_knifer "1"             // Slay knifer after revert
sm_cknife_kban_knifer "1"             // Show ban menu after revert
sm_cknife_kban_reason "Knifing..."    // Default ban reason
sm_cknife_print_message_type "1"      // Message visibility (0=all, 1=admins)
```

## Critical Implementation Details

### State Preservation
- **Timing**: Save player state in `OnTakeDamage` before infection
- **Data**: Health, armor, weapons, grenades, position, equipment
- **Restoration**: Full state restoration including entity references

### Memory Management
```sourcepawn
// Correct pattern for ArrayList cleanup
for (int i = 0; i < g_arAllKnives.Length; i++) {
    CKnife knife;
    g_arAllKnives.GetArray(i, knife, sizeof(knife));
    delete knife.deadPeople;  // Clean up nested ArrayLists
}
g_arAllKnives.Clear();  // Safe to clear after cleanup
```

### Timer Management
```sourcepawn
delete g_hCheckAllKnivesTimer;  // Safe delete without null check
g_hCheckAllKnivesTimer = CreateTimer(60.0, CheckAllKnives_Timer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
```

## Common Issues & Solutions

### Weapon Restoration
- **Problem**: Weapons disappearing after restoration
- **Solution**: Store both classname strings and entity references
- **Validation**: Check `EntRefToEntIndex` before using stored weapon entities

### Performance Considerations
- **Timer Optimization**: 60-second cleanup timer instead of frequent checks
- **Early Returns**: Multiple validation checks to avoid unnecessary processing
- **Memory**: Proper cleanup of dynamic data structures

### Integration Issues
- **KnifeMode**: Conditional compilation with `#if defined _KnifeMode_Included`
- **Plugin Load Order**: Ensure ZombieReloaded loads before this plugin
- **Event Timing**: Use appropriate hook modes for reliable event handling

## Development Guidelines

### Making Changes
1. **Understand Context**: This plugin tracks complex game state chains
2. **Test Thoroughly**: Always test with multiple players and scenarios
3. **Memory Safety**: Pay special attention to ArrayList and Handle cleanup
4. **Backwards Compatibility**: Maintain compatibility with existing configurations
5. **Performance**: Consider impact on frequently called functions (damage hooks)

### Debugging Tips
- **Logging**: Use `LogAction` for admin actions and critical events
- **Chat Messages**: Use MultiColors for consistent admin messaging
- **State Validation**: Check client validity before accessing client data
- **Timer Debugging**: Monitor timer lifecycle and cleanup

### Version Control
- **Semantic Versioning**: Follow MAJOR.MINOR.PATCH format
- **Plugin Version**: Update version constant in plugin source
- **Dependencies**: Keep sourceknight.yaml dependencies current
- **Testing**: Validate changes with full dependency chain

## Security Considerations
- **Admin Permissions**: All commands require `ADMFLAG_KICK` or higher
- **Input Validation**: Validate all client and user IDs before use
- **State Integrity**: Prevent manipulation of saved game states
- **Resource Limits**: Timer cleanup prevents memory leaks from abandoned knives

This plugin is critical for maintaining fair gameplay in zombie-themed servers. Always prioritize game state integrity and player experience when making modifications.