// Spec 010 FR-021: the six steps of the getting-started guide, in the order of Story 5.

export interface GuideStep {
	title: string;
	body: string;
	/** A step that can do what it describes (step 2 opens the example). */
	action?: 'open-example';
}

export const GUIDE_STEPS: readonly GuideStep[] = [
	{
		title: 'Welcome',
		body: 'SentaiTask lets you compose maintenance flows for this IRIS instance and run them now or on a schedule.'
	},
	{
		title: 'Open the example',
		body: 'Open example flow opens a small ready-made flow of safe, read-only checks. Run it to see SentaiTask working on this instance.',
		action: 'open-example'
	},
	{
		title: 'Build a flow',
		body: 'Drag steps from the palette onto the canvas, connect them to set their order, and edit their parameters in the inspector.'
	},
	{
		title: 'Validate and run',
		body: 'Validate flow checks the flow against this instance. Run now starts it and shows each step live.'
	},
	{
		title: 'Save, Save as, Open',
		body: 'Save flow keeps your changes to this flow, and editing its name renames it. Save as… (in More) makes a copy, Open flow… returns to any saved flow, and New flow (in More) starts empty.'
	},
	{
		title: 'Schedule and explore',
		body: 'Schedule in Task Manager hands the flow to the platform scheduler. Task catalog shows the tasks on this instance, and Targets shows the remote servers.'
	}
];
