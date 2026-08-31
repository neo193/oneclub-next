const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-razorpay-signature","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const env=(name:string)=>{const value=Deno.env.get(name);if(!value)throw new Error(`Missing server secret: ${name}`);return value;};
const supabaseUrl=env("SUPABASE_URL"),serviceKey=env("SUPABASE_SERVICE_ROLE_KEY"),anonKey=env("SUPABASE_ANON_KEY");
const razorpayKey=env("RAZORPAY_KEY_ID"),razorpaySecret=env("RAZORPAY_KEY_SECRET");
const basic=`Basic ${btoa(`${razorpayKey}:${razorpaySecret}`)}`;

async function rest(path:string,options:RequestInit={}){const response=await fetch(`${supabaseUrl}/rest/v1/${path}`,{...options,headers:{apikey:serviceKey,Authorization:`Bearer ${serviceKey}`,"Content-Type":"application/json",...(options.headers||{})}});const data=await response.json().catch(()=>null);if(!response.ok)throw new Error(data?.message||"Database request failed");return data;}
async function currentUser(req:Request){const authorization=req.headers.get("authorization");if(!authorization)throw new Error("Sign in required");const response=await fetch(`${supabaseUrl}/auth/v1/user`,{headers:{apikey:anonKey,authorization}});if(!response.ok)throw new Error("Session is invalid");return await response.json();}
async function requireAdmin(userId:string){const profiles=await rest(`profiles?select=app_role&id=eq.${userId}`);if(profiles[0]?.app_role!=="admin")throw new Error("Administrator permission required");}
async function requireOpenMembershipOffer(userId:string,extendCheckout=false){const profiles=await rest(`profiles?select=membership_state,payment_offer_expires_at&id=eq.${userId}`);const profile=profiles[0];if(profile?.membership_state!=="payment_pending")throw new Error("Membership is not awaiting payment");const deadline=new Date(profile.payment_offer_expires_at||0);if(deadline<=new Date())throw new Error("This membership payment offer has expired");if(extendCheckout){const checkoutDeadline=new Date(Date.now()+15*60*1000);if(deadline<checkoutDeadline)await rest(`profiles?id=eq.${userId}`,{method:"PATCH",headers:{Prefer:"return=minimal"},body:JSON.stringify({payment_offer_expires_at:checkoutDeadline.toISOString(),updated_at:new Date().toISOString()})});}return profile;}
async function razorpay(path:string,options:RequestInit={}){const response=await fetch(`https://api.razorpay.com/v1/${path}`,{...options,headers:{Authorization:basic,"Content-Type":"application/json",...(options.headers||{})}});const data=await response.json().catch(()=>null);if(!response.ok)throw new Error(data?.error?.description||"Razorpay request failed");return data;}
async function hmac(message:string,secret=razorpaySecret){const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);const bytes=new Uint8Array(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(message)));return [...bytes].map(x=>x.toString(16).padStart(2,"0")).join("");}
function equal(a:string,b:string){if(a.length!==b.length)return false;let difference=0;for(let i=0;i<a.length;i++)difference|=a.charCodeAt(i)^b.charCodeAt(i);return difference===0;}
const refundState=(status:string)=>status==="processed"?"processed":status==="failed"?"failed":"processing";
async function recordRefund(bookingId:string,refund:any,source:string,actorId:string|null){await rest("rpc/record_razorpay_refund",{method:"POST",body:JSON.stringify({p_booking_id:bookingId,p_refund_id:refund.id||null,p_status:refundState(refund.status),p_source:source,p_actor_id:actorId,p_failure_reason:refund.status==="failed"?(refund.error_description||"Razorpay reported a failed refund"):null})});}
async function handleWebhook(raw:string,signature:string){const secret=env("RAZORPAY_WEBHOOK_SECRET");if(!equal(await hmac(raw,secret),signature))throw new Error("Webhook signature is invalid");const event=JSON.parse(raw);if(!["refund.created","refund.processed","refund.failed"].includes(event.event))return json({received:true,ignored:true});const refund=event.payload?.refund?.entity;if(!refund?.payment_id||!refund?.id)throw new Error("Refund payload is incomplete");const attempts=await rest(`payment_attempts?select=booking_id&purpose=eq.event&razorpay_payment_id=eq.${encodeURIComponent(refund.payment_id)}&limit=1`);if(!attempts[0]?.booking_id)return json({received:true,unmatched:true});await recordRefund(attempts[0].booking_id,refund,"webhook",null);return json({received:true});}

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({message:"Method not allowed"},405);
  try{
    const raw=await req.text();const webhookSignature=req.headers.get("x-razorpay-signature");
    if(webhookSignature)return await handleWebhook(raw,webhookSignature);
    const user=await currentUser(req);const input=JSON.parse(raw||"{}");
    if(input.action==="refund_issue"||input.action==="refund_reconcile"){
      await requireAdmin(user.id);
      const context=await rest("rpc/get_refund_context",{method:"POST",body:JSON.stringify({p_booking_id:input.booking_id})});
      if(context.payment_status==="refunded"||context.refund_status==="processed")return json({reconciled:true,status:"processed",refund_id:context.razorpay_refund_id});
      const existing=await razorpay(`payments/${encodeURIComponent(context.razorpay_payment_id)}/refunds`);
      const matched=existing.items?.find((refund:any)=>refund.amount===context.amount_paise&&["pending","processed"].includes(refund.status));
      if(matched){await recordRefund(context.booking_id,matched,"manual_reconciliation",user.id);return json({reconciled:true,status:refundState(matched.status),refund_id:matched.id});}
      if(input.action==="refund_reconcile")return json({reconciled:false});
      const refund=await razorpay(`payments/${encodeURIComponent(context.razorpay_payment_id)}/refund`,{method:"POST",body:JSON.stringify({amount:context.amount_paise,speed:"normal",notes:{booking_id:context.booking_id,source:"oneclub_refund_workspace"}})});
      await recordRefund(context.booking_id,refund,"workspace",user.id);
      return json({issued:true,status:refundState(refund.status),refund_id:refund.id});
    }
    if(input.action==="create"){
      let amount:number,bookingId:null|string=null,description:string;
      if(input.purpose==="membership"){
        await requireOpenMembershipOffer(user.id,true);amount=5000000;description="One Club Membership";
      }else if(input.purpose==="event"){
        const bookings=await rest(`event_bookings?select=id,amount_paise,status,reservation_expires_at,event_id&member_id=eq.${user.id}&id=eq.${input.booking_id}`);const booking=bookings[0];if(!booking||booking.status!=="pending_payment"||new Date(booking.reservation_expires_at)<=new Date())throw new Error("Event reservation has expired or is not payable");amount=booking.amount_paise;bookingId=booking.id;description="One Club Event Booking";await rest(`event_bookings?id=eq.${booking.id}`,{method:"PATCH",headers:{Prefer:"return=minimal"},body:JSON.stringify({reservation_expires_at:new Date(Date.now()+15*60*1000).toISOString(),updated_at:new Date().toISOString()})});
      }else throw new Error("Unsupported payment purpose");
      const order=await razorpay("orders",{method:"POST",body:JSON.stringify({amount,currency:"INR",receipt:`oc_${crypto.randomUUID().slice(0,18)}`,notes:{purpose:input.purpose,user_id:user.id,reference:bookingId||"membership"}})});
      const attempts=await rest("payment_attempts",{method:"POST",headers:{Prefer:"return=representation"},body:JSON.stringify({user_id:user.id,purpose:input.purpose,booking_id:bookingId,amount_paise:amount,razorpay_order_id:order.id})});
      return json({attempt_id:attempts[0].id,key_id:razorpayKey,order_id:order.id,amount,currency:"INR",description});
    }
    if(input.action==="reconcile"){
      if(input.purpose==="membership")await requireOpenMembershipOffer(user.id);
      const filter=input.purpose==="event"?`purpose=eq.event&booking_id=eq.${input.booking_id}`:"purpose=eq.membership";
      const attempts=await rest(`payment_attempts?select=*&user_id=eq.${user.id}&status=eq.created&${filter}&order=created_at.desc`);
      for(const attempt of attempts){const payments=await razorpay(`orders/${encodeURIComponent(attempt.razorpay_order_id)}/payments`);const captured=payments.items?.find((p:any)=>p.status==="captured"&&p.amount===attempt.amount_paise&&p.order_id===attempt.razorpay_order_id);if(captured){const purpose=await rest("rpc/finalize_razorpay_payment",{method:"POST",body:JSON.stringify({p_attempt_id:attempt.id,p_payment_id:captured.id})});return json({recovered:true,purpose});}}
      return json({recovered:false});
    }
    if(input.action==="verify"){
      const attempts=await rest(`payment_attempts?select=*&id=eq.${input.attempt_id}&user_id=eq.${user.id}`);const attempt=attempts[0];if(!attempt)throw new Error("Payment attempt not found");if(attempt.razorpay_order_id!==input.razorpay_order_id)throw new Error("Order does not match");
      if(attempt.purpose==="membership")await requireOpenMembershipOffer(user.id);
      const expected=await hmac(`${attempt.razorpay_order_id}|${input.razorpay_payment_id}`);if(!equal(expected,String(input.razorpay_signature||"")))throw new Error("Payment signature is invalid");
      let payment=await razorpay(`payments/${encodeURIComponent(input.razorpay_payment_id)}`);if(payment.order_id!==attempt.razorpay_order_id||payment.amount!==attempt.amount_paise)throw new Error("Payment details do not match");
      if(payment.status==="authorized")payment=await razorpay(`payments/${encodeURIComponent(payment.id)}/capture`,{method:"POST",body:JSON.stringify({amount:attempt.amount_paise,currency:"INR"})});if(payment.status!=="captured")throw new Error("Payment has not been captured");
      const purpose=await rest("rpc/finalize_razorpay_payment",{method:"POST",body:JSON.stringify({p_attempt_id:attempt.id,p_payment_id:payment.id})});return json({verified:true,purpose});
    }
    throw new Error("Unsupported action");
  }catch(error){return json({message:error instanceof Error?error.message:"Payment request failed"},400);}
});
