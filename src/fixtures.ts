import { emptyDocument, newBlock } from '../shared/domain';
export function exampleDocument() {
  const document = emptyDocument();
  document.blocks = [
    newBlock('Before we begin', 'heading'),
    newBlock('What would make this conversation useful?'),
    newBlock('Notes', 'heading'),
    newBlock(
      'We are aligned on the goals for this quarter and the constraints we are working within. To make progress, we need to agree on priorities and a clear next step.',
    ),
    newBlock(
      'I will listen for trade-offs, note decisions, and capture action items. If something is unclear, I will ask for clarification so we leave with shared understanding.',
    ),
  ];
  return document;
}
