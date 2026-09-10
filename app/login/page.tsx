import { AuthForm } from "@/components/auth-form";
export const metadata = { title: "Log in" };
export default async function Login({ searchParams }: { searchParams: Promise<{ next?: string; error?: string }> }) {
  const params = await searchParams;
  return <AuthForm mode="login" next={params.next} initialMessage={params.error ? "This email link is invalid or expired. Try logging in, or request a new link." : ""} />;
}
