import type {Season} from "@/lib/seasons";
export type BankEntry={id:string;delta:number;balance_after:number;cash_after:number;created_at:string};
export type BankState={season:Season;server_time:string;playable:boolean;player:{id:string;handle:string;cash:number};balance:number;opened_at:string|null;settings:{bank_deposits_enabled:number;bank_max_transfer:number};can_manage:boolean;offset:number;page_size:number;total:number;history:BankEntry[];totals:{deposited:number;withdrawn:number;transfers:number};flow:{day:string;deposits:number;withdrawals:number}[]};
export type BankTransfer={action:"deposit"|"withdraw";payload:{season_id:string;request_id:string;amount:number}};
