import { getPublicIpWithFallback } from "@dokploy/server/wss/utils";
import { and, eq, isNotNull } from "drizzle-orm";
import { scheduleJob } from "node-schedule";
import { db } from "../../db/index";
import { user as userSchema } from "../../db/schema/user";

export const LICENSE_KEY_URL =
	// process.env.NODE_ENV === "development"
	// 	? "http://localhost:4002"
	"https://licenses-api.dokploy.com";

export const initEnterpriseBackupCronJobs = async () => {
	// Cronjob disabled for internal enterprise use
};

export const validateLicenseKey = async (_licenseKey: string) => {
	return true;
};
