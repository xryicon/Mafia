export const playerId = "11111111-1111-4111-8111-111111111111";
const encode = value => Buffer.from(JSON.stringify(value)).toString("base64url");
export const token = encode({alg:"HS256",typ:"JWT"}) + "." + encode({sub:playerId,role:"authenticated",aud:"authenticated",iss:"http://127.0.0.1:54329/auth/v1",exp:2100000000,iat:1789062011}) + ".test-signature";
export const user = {id:playerId,aud:"authenticated",role:"authenticated",email:"player@example.test",app_metadata:{provider:"email"},user_metadata:{},email_confirmed_at:"2026-09-10T00:00:00Z",created_at:"2026-09-10T00:00:00Z"};
export const cookie = "base64-" + encode({access_token:token,refresh_token:"test-refresh",expires_in:3600,expires_at:2100000000,token_type:"bearer",user});
