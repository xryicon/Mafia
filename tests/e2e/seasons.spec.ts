import {test,expect} from "@playwright/test";
import {cookie} from "../fixtures/identity.mjs";
test("mobile rankings, profile and Owner season controls",async({page,context})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Requires isolated fixture");
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);
 await page.setViewportSize({width:390,height:844});
 await page.goto("/seasons");
 await expect(page.getByRole("heading",{name:"A place in history."})).toBeVisible();
 await expect(page.getByRole("table")).toContainText("#1");
 await page.getByRole("table").getByRole("link").click();
 await expect(page.getByRole("heading",{name:"Previous seasons",exact:true})).toBeVisible();
 await page.goto("/seasons");
 await page.getByRole("button",{name:"Hall of Fame",exact:true}).click();
 await expect(page.getByText("The first champions will appear",{exact:false})).toBeVisible();
 await page.getByRole("button",{name:"Owner controls",exact:true}).click();
 await expect(page.getByRole("heading",{name:"Create season",exact:true})).toBeVisible();
 await expect(page.getByRole("heading",{name:"Lock season",exact:true})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
});
