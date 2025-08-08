use starknet::ContractAddress;
use starknet::get_block_timestamp;
use super::*;
use crate::models::session::SessionKey;

// Constants for session management
pub const MIN_SESSION_DURATION: u64 = 3600; // 1 hour in seconds
pub const MAX_SESSION_DURATION: u64 = 86400; // 24 hours in seconds
pub const MAX_TRANSACTIONS_PER_SESSION: u32 = 1000;
pub const AUTO_RENEWAL_THRESHOLD: u64 = 300; // 5 minutes in seconds
pub const DEFAULT_RENEWAL_DURATION: u64 = 3600; // 1 hour in seconds

// Constants for session limits per player
pub const MAX_ACTIVE_SESSIONS_PER_PLAYER: u32 = 5; // Maximum active sessions per player
pub const SESSION_CLEANUP_THRESHOLD: u64 = 86400; // 24 hours - sessions older than this are considered inactive

// Error constants for session validation
pub const ERROR_INVALID_SESSION: felt252 = 'INVALID_SESSION';
pub const ERROR_SESSION_EXPIRED: felt252 = 'SESSION_EXPIRED';
pub const ERROR_NO_TRANSACTIONS_LEFT: felt252 = 'NO_TRANSACTIONS_LEFT';
pub const ERROR_UNAUTHORIZED_PLAYER: felt252 = 'UNAUTHORIZED_PLAYER';
pub const ERROR_SESSION_NOT_ACTIVE: felt252 = 'SESSION_NOT_ACTIVE';

// Helper function to calculate time remaining for a session
pub fn calculate_session_time_remaining(session: SessionKey) -> u64 {
    let current_time = get_block_timestamp();
    if current_time >= session.expires_at {
        0
    } else {
        session.expires_at - current_time
    }
}

// Helper function to calculate time remaining for a session with custom time (for testing)
pub fn calculate_session_time_remaining_with_time(session: SessionKey, current_time: u64) -> u64 {
    if current_time >= session.expires_at {
        0
    } else {
        session.expires_at - current_time
    }
}

// Helper function to check if session is expired
pub fn is_session_expired(session: SessionKey) -> bool {
    let current_time = get_block_timestamp();
    current_time >= session.expires_at
}

// Helper function to check if session is expired with custom time (for testing)
pub fn is_session_expired_with_time(session: SessionKey, current_time: u64) -> bool {
    current_time >= session.expires_at
}

// Helper function to check if session needs renewal
pub fn needs_auto_renewal(session: SessionKey) -> bool {
    let time_remaining = calculate_session_time_remaining(session);
    time_remaining < AUTO_RENEWAL_THRESHOLD && time_remaining > 0
}

// Helper function to check if session needs renewal with custom time (for testing)
pub fn needs_auto_renewal_with_time(session: SessionKey, current_time: u64) -> bool {
    let time_remaining = calculate_session_time_remaining_with_time(session, current_time);
    time_remaining < AUTO_RENEWAL_THRESHOLD && time_remaining > 0
}

// Helper function to check if session has transactions left
pub fn has_transactions_left(session: SessionKey) -> bool {
    session.used_transactions < session.max_transactions
}

// Helper function to validate session basic parameters
pub fn validate_session_parameters(session: SessionKey, caller: ContractAddress) -> bool {
    // Check if session exists
    if session.session_id == 0 {
        return false;
    }

    // Check if session belongs to caller
    if session.player_address != caller {
        return false;
    }

    // Check if session is valid
    if !session.is_valid {
        return false;
    }

    // Check if session is active
    if session.status != 0 {
        return false;
    }

    // Check if session is not expired
    if is_session_expired(session) {
        return false;
    }

    // Check if session has transactions left
    if !has_transactions_left(session) {
        return false;
    }

    true
}

// Helper function to validate session basic parameters with custom time (for testing)
pub fn validate_session_parameters_with_time(
    session: SessionKey, caller: ContractAddress, current_time: u64,
) -> bool {
    // Check if session exists
    if session.session_id == 0 {
        return false;
    }

    // Check if session belongs to caller
    if session.player_address != caller {
        return false;
    }

    // Check if session is valid
    if !session.is_valid {
        return false;
    }

    // Check if session is active
    if session.status != 0 {
        return false;
    }

    // Check if session is not expired
    if is_session_expired_with_time(session, current_time) {
        return false;
    }

    // Check if session has transactions left
    if !has_transactions_left(session) {
        return false;
    }

    true
}

// Helper function to get session status as a number
pub fn get_session_status(session: SessionKey) -> u8 {
    if session.session_id == 0 {
        return 3; // Invalid session
    }
    if !session.is_valid {
        return 2; // Revoked session
    }
    if session.status != 0 {
        return 1; // Inactive session
    }
    if is_session_expired(session) {
        return 4; // Expired session
    }
    if !has_transactions_left(session) {
        return 5; // No transactions left
    }
    0 // Valid session
}

// Helper function to get session status as a number with custom time (for testing)
pub fn get_session_status_with_time(session: SessionKey, current_time: u64) -> u8 {
    if session.session_id == 0 {
        return 3; // Invalid session
    }
    if !session.is_valid {
        return 2; // Revoked session
    }
    if session.status != 0 {
        return 1; // Inactive session
    }
    if is_session_expired_with_time(session, current_time) {
        return 4; // Expired session
    }
    if !has_transactions_left(session) {
        return 5; // No transactions left
    }
    0 // Valid session
}

// Function to check if a player can create more sessions
// This should be called before creating a new session
pub fn can_player_create_session(
    player_sessions: Array<SessionKey>,
    current_time: u64,
) -> bool {
    let mut active_count = 0;
    let mut i = 0;
    let len = player_sessions.len();
    
    while i < len {
        let session = player_sessions.at(i);
        
        // Count only valid, active, non-expired sessions
        if (*session).is_valid 
            && (*session).status == 0 
            && current_time < (*session).expires_at 
            && (*session).used_transactions < (*session).max_transactions {
            active_count += 1;
        }
        
        i += 1;
    };
    
    return active_count < MAX_ACTIVE_SESSIONS_PER_PLAYER;
}  

// Centralized session validation function that all systems should use
// This ensures consistency across all systems and includes auto-renewal
pub fn validate_session_for_action_centralized(
    session: SessionKey, caller: ContractAddress, current_time: u64,
) -> (bool, SessionKey) {
    // First, validate the session using our helper
    if !validate_session_parameters_with_time(session, caller, current_time) {
        return (false, session);
    }

    // Check if session needs auto-renewal (less than 5 minutes remaining)
    let time_remaining = calculate_session_time_remaining_with_time(session, current_time);
    
    if time_remaining < AUTO_RENEWAL_THRESHOLD && time_remaining > 0 {
        // Auto-renew the session
        let mut renewed_session = session;
        renewed_session.expires_at = current_time + DEFAULT_RENEWAL_DURATION;
        renewed_session.last_used = current_time;
        renewed_session.max_transactions = 100; // Reset to default
        renewed_session.used_transactions = 0; // Reset transaction count
        
        return (true, renewed_session);
    }
    
    // Session is valid and doesn't need renewal
    (true, session)
}
