// Decorative city activity, never another player or a searchable vehicle.
export function ScavengingStreetLife(){
 return <g className="scav-street-life" pointerEvents="none" aria-hidden="true">
  {[{x:175,y:83},{x:432,y:307},{x:645,y:577},{x:860,y:313},{x:350,y:580}].map((p,i)=><g key={i} className="scav-lamp" style={{animationDelay:`-${i*1.7}s`}}><circle cx={p.x} cy={p.y} r="23" fill="#e9ab46" opacity=".09"/><circle cx={p.x} cy={p.y} r="8" fill="#ffc877" opacity=".22"/><circle cx={p.x} cy={p.y} r="2" fill="#ffe0a6"/></g>)}
  {[{x:205,y:235},{x:680,y:430},{x:830,y:180}].map((p,i)=><g key={i} transform={`translate(${p.x} ${p.y})`}><ellipse className="scav-steam" cx="0" cy="0" rx="23" ry="9" fill="#b6c6c0" style={{animationDelay:`-${i*3}s`}}/></g>)}
  <g className="scav-traffic scav-traffic-east"><rect x="-8" y="-4" width="16" height="8" rx="3" fill="#293337" stroke="#a68a60"/><path d="M8 -3l24 -5v16L8 3" fill="#eed394" opacity=".13"/><circle cx="8" cy="-3" r="1.4" fill="#ffe7b3"/><circle cx="8" cy="3" r="1.4" fill="#ffe7b3"/></g>
  <g className="scav-traffic scav-traffic-west"><rect x="-8" y="-4" width="16" height="8" rx="3" fill="#333331" stroke="#948264"/><path d="M-8 -3l-24 -5v16l24 -5" fill="#eed394" opacity=".13"/><circle cx="-8" cy="-3" r="1.4" fill="#ffe7b3"/><circle cx="-8" cy="3" r="1.4" fill="#ffe7b3"/></g>
 </g>;
}
