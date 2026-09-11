export type CitySeason = { id: string; name: string; status: string };
export type ChatMessage = { id: string; player_id: string; username: string; body: string; created_at: string; role: string };
export type SocialState = { player_id: string; username: string; username_claimed: boolean; online_count: number; window_seconds: number; poll_seconds: number; season: CitySeason; permissions: string[]; muted: boolean; chat: ChatMessage[]; server_time: string };
export type DirectoryPlayer = { id: string; username: string; respect: number; rank: number; online: boolean; role: string };
export type DirectoryState = { players: DirectoryPlayer[]; total: number; offset: number; page_size: number; my_rank: number | null; online_count: number; season: CitySeason; server_time: string };
