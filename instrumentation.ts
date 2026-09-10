import type { Instrumentation } from "next";
import { errorRecord } from "@/lib/error-log";
export const onRequestError:Instrumentation.onRequestError=(error,request,context)=>{
 console.error(JSON.stringify(errorRecord(error,request.method,context.routePath)));
};
