import { defineCollection, z } from "astro:content";

const postsCollection = defineCollection({
	schema: z.object({
		title: z.string(),
		published: z.date(),
		updated: z.date().optional(),
		draft: z.boolean().optional().default(false),
		description: z.string().optional().default(""),
		image: z.string().optional().default(""),
		tags: z.array(z.string()).optional().default([]),
		category: z.string().optional().nullable().default(""),
		lang: z.string().optional().default(""),

		/* For internal use */
		prevTitle: z.string().default(""),
		prevSlug: z.string().default(""),
		nextTitle: z.string().default(""),
		nextSlug: z.string().default(""),
	}),
});
const specCollection = defineCollection({
	schema: z.object({ title: z.string(), description: z.string() }),
});
export const collections = {
	posts: postsCollection,
	spec: specCollection,
 projects: defineCollection({schema: z.object({title:z.string().min(1),description:z.string().default(""),status:z.enum(["Aktif","Selesai","Arsip"]).default("Aktif"),url:z.string().url().refine(v=>/^https?:/.test(v)).optional(),order:z.number().default(0),draft:z.boolean().default(false)})}),
};
