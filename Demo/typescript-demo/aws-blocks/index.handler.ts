import { createLambdaHandler } from '@aws-blocks/blocks/lambda-handler';
import * as backend from './index.js';

export const handler = createLambdaHandler(backend);