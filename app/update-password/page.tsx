import { AuthForm } from "@/components/auth-form";
import { requireUser } from "@/lib/auth";
export const dynamic = "force-dynamic";
export const metadata = { title: "Choose a new password" };
export default async function UpdatePassword() {
  await requireUser("/update-password");
  return <AuthForm mode="update-password" />;
}
