CREATE TABLE `alerts` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`trip_id` text NOT NULL,
	`kind` text NOT NULL,
	`message` text NOT NULL,
	`resolved_at` text,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	FOREIGN KEY (`trip_id`) REFERENCES `trips`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_alerts_open_trip` ON `alerts` (`resolved_at`,`trip_id`);--> statement-breakpoint
CREATE TABLE `location_updates` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`trip_id` text NOT NULL,
	`latitude` real NOT NULL,
	`longitude` real NOT NULL,
	`accuracy_meters` real,
	`altitude_meters` real,
	`battery_percent` integer,
	`recorded_at` text NOT NULL,
	`received_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	FOREIGN KEY (`trip_id`) REFERENCES `trips`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_locations_trip_recorded` ON `location_updates` (`trip_id`,`recorded_at`);--> statement-breakpoint
CREATE TABLE `trips` (
	`id` text PRIMARY KEY NOT NULL,
	`code` text NOT NULL,
	`access_token` text NOT NULL,
	`visitor_name` text NOT NULL,
	`emergency_phone` text,
	`route_name` text NOT NULL,
	`expected_return_at` text NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`started_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	`completed_at` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `trips_code_unique` ON `trips` (`code`);--> statement-breakpoint
CREATE UNIQUE INDEX `trips_access_token_unique` ON `trips` (`access_token`);--> statement-breakpoint
CREATE INDEX `idx_trips_status_expected_return` ON `trips` (`status`,`expected_return_at`);--> statement-breakpoint
PRAGMA optimize;
